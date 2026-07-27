# Close reminder tab on SessionEnd + GC dead iTerm2 sessions

## Goal

Two related cleanups keyed off a Claude Code session going away:

1. When a Claude Code session ends (`SessionEnd`), clear that session's reminder
   tab from the app's right-edge tab strip, so a finished session leaves no
   stale tab.
2. When an iTerm2 pane is actually closed, drop that session's in-memory color +
   inject-once flag (and, as a backstop, its dead tab) via lazy reconcile, so
   stale entries do not accumulate.

## Background / Confirmed facts

- Tab-clearing already exists: a `type: "resolve"` payload →
  `ReminderCoordinator.handle` → `store.remove(sessionUUID:)`
  (`Sources/ClaudeItermMate/ReminderCoordinator.swift:114-117`). Only the
  AskUserQuestion PostToolUse (`--event ask-done`) hook emits it today
  (`mate-notify.js:346-359`).
- Session identity comes from `ITERM_SESSION_ID` via `deriveSession`
  (`mate-notify.js:135-142`); still present when a `SessionEnd` hook runs.
- Hooks are registered by `HookInstaller.install()` with an idempotent,
  per-event, marker-scoped append (`settingsByAddingHook`,
  `HookInstaller.swift:57-84`) and removed by `settingsByRemovingHook`
  (`HookInstaller.swift:90-117`). `install()` re-runs on every launch.
- In-memory session state lives in `ReminderCoordinator`:
  `coloredSessions: [String: String]` (hex dedup, `ReminderCoordinator.swift:78`)
  and `colorInjectedSessions: Set<String>` (inject-once flag, `:84`). Both are
  in-memory only, cleared on app restart.
- The reminder `present()` path already probes iTerm2 off-main once per event
  (`probe.canFind`, `ReminderCoordinator.swift:134-138`).
- `ItermSessionLookup.liveSessionIDs()` returns the full live session-id set
  (`Set<String>?`, `nil` on failure/`it2` missing; `ItermSessionLookup.swift:30`).
  The `ItermSessionProbe` protocol currently only requires `canFind`
  (`ItermSessionLookup.swift:6-8`); three test `StubProbe`s implement just that
  (`ReminderCoordinatorTests.swift:28`, `PaneColoringTests.swift:8`,
  `NonItermSessionTests.swift:23`).

## Decisions

- "tab" = the app's reminder tab, reusing the existing `resolve` chain. The app
  never touches iTerm2 panes/tabs.
- `SessionEnd` fires on **every** reason (`clear` / `logout` /
  `prompt_input_exit` / `other`) — no reason filtering.
- `SessionEnd` (Claude exit) does **not** clear color memory: the pane may still
  be alive and reused. This is satisfied for free — `resolve` only calls
  `store.remove` and never touches `coloredSessions` / `colorInjectedSessions`.
- Pane-close detection uses **lazy reconcile**, not a resident monitor: reuse
  the existing `present()` background probe to fetch the live session set and GC
  in-memory entries whose session is gone. Zero resident process, zero extra
  `it2` calls. Trade-off: cleanup happens on the *next* reminder event, not at
  the instant the pane closes (acceptable — memory is tiny and cleared on
  restart).
- Reconcile only runs when the live set is known (`liveSessionIDs() != nil`). On
  probe failure it is skipped entirely, so a transient `it2` failure never GCs
  live sessions.

## Requirements

- R1: Add a `--event session-end` handler to `mate-notify.js` sending a
  `type:"resolve"` payload (`session_uuid`, `cwd`, `timestamp`), mirroring
  `handleAskDone`.
- R2: `eventMode` recognizes `session-end`; unknown/absent modes still fall back
  to `stop`.
- R3: The handler only fires for focusable (iTerm2) sessions and skips SDK /
  headless, matching the `ask-done` guards (`mate-notify.js:353-357`).
- R4: `HookInstaller.install()` registers a `SessionEnd` hook (matcher `""`,
  command `node "<script>" --event session-end`, marker `mate-notify.js`),
  idempotent and per-event scoped.
- R5: `HookInstaller.uninstall()` removes the `SessionEnd` hook.
- R6: Extend `ItermSessionProbe` with `liveSessionIDs() -> Set<String>?` plus a
  protocol-extension default returning `nil`, so existing stubs compile
  unchanged and skip GC.
- R7: In the reminder path, fetch the live set once off-main; derive `findable`
  from it (`live?.contains(uuid) ?? canFind(uuid)` — no double `it2` call), and
  when `live != nil` run reconcile: drop `coloredSessions` / `colorInjectedSessions`
  entries whose session id is not in the live set.
- R8: Reconcile also removes `store` items whose session id is not in the live
  set (backstop for a force-closed pane, where `SessionEnd` may not fire so R1
  never runs).

## Acceptance Criteria

- [ ] AC1: `node --test 'Tests/js/**/*.test.js'` passes, incl.
  `eventMode(["--event","session-end"]) == "session-end"`.
- [ ] AC2: `swift test --filter HookInstallerTests` passes, incl. SessionEnd
  add-once-idempotent and remove cases.
- [ ] AC3: `swift test --filter ReminderCoordinatorTests` passes with a new stub
  returning a live set: a reminder event GCs a color/flag entry whose session is
  absent from the set, and keeps entries whose session is present; when
  `liveSessionIDs()` is `nil` nothing is GC'd.
- [ ] AC4: Manual — iTerm2 Claude session, trigger a Stop so a tab appears, then
  `/exit`; the tab disappears. Force-close a different session's pane, trigger
  any other session's Stop; the dead tab and its color/flag entry are gone.
- [ ] AC5: Existing behavior intact: full `swift test` and JS suite pass; the
  four other `mate-notify.js` hooks unaffected; existing `present()`/coloring
  tests unchanged (stubs default `liveSessionIDs()` to `nil`).

## Out of scope

- Closing iTerm2 panes/tabs from the app.
- Filtering by `SessionEnd` reason.
- Resident iTerm2 API monitor or a periodic reconcile timer (rejected in favor
  of lazy reconcile).
- Clearing color memory on `SessionEnd` (deliberately kept — pane may be reused).
