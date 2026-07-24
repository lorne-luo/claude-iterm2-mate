# Implement: Session waiting-vs-completed status

Branch: `show-usage` is current; create a feature branch off it (or off `main`
per repo convention) before starting — do not commit to `main`.

## Ordered checklist

### Phase A — wire the status field end to end (no UI yet)
1. `Store/SessionStatus.swift`: add `enum SessionStatus { case completed, waiting }`
   (Equatable). → verify: `swift build`.
2. `Server/NotifyPayload.swift`: add `status: String?` + CodingKey + `decodeIfPresent`;
   add `var sessionStatus: SessionStatus`. → verify: unit test decode with
   status present / absent / unknown value (AC9).
3. `Store/ReminderStore.swift`: add `var status: SessionStatus` to `ReminderItem`;
   set it in `upsert` from `p.sessionStatus`. → verify: existing ReminderStore
   tests still pass; add a test that upsert carries status and that a later
   completed payload replaces a waiting item (AC5, store half).

### Phase B — JS hook (both triggers)
4. `Resources/mate-notify.js`: extract shared `gitInfo`, session-UUID/focusable
   derivation, and socket-send into functions. Add `classifyStopStatus(msg)`
   (pure): "waiting" iff (a) trimmed msg ends in `?`/`？`, OR (b) it ends on a
   sequential numbered-choice menu — final non-empty line `^\s*\d+[.)]\s+\S`,
   numbered lines run `1..k` (k≥2). Use it to set `fields.status` in Stop mode.
   → verify: node unit test of `classifyStopStatus` across: ends `?`, ends `？`,
   ends `.`/`!`/none, trailing whitespace/newlines, empty, the reference
   numbered menu (waiting), a mid-body numbered list ending in prose (completed),
   a non-sequential/single numbered line (completed) (AC1, AC2).
5. Same file: add `--event notification` mode — parse argv, branch to a
   `handleNotification(input)` that checks `notification_type === "permission_prompt"`
   (else silent exit), builds a `status: "waiting"` payload, sends over socket,
   NO desktop fallback. Factor `shouldSendNotification(input)` (pure). → verify:
   node unit test: permission_prompt -> send-shaped payload; idle_prompt/other ->
   no-op (AC4).
6. Manual socket smoke test (per CLAUDE.md python client): send a `status:waiting`
   payload and a `status:completed` payload; confirm app shows amber vs normal
   after Phase D. Also empirically confirm `ITERM_SESSION_ID` is present in a real
   Notification hook run (risk in prd.md) — run a real permission prompt with a
   temporary logging line, or inspect via a throwaway hook.

### Phase C — coordinator no-repeat-toast (R4)
7. `ReminderCoordinator.swift`: in/just before `present`, add the guard: if
   incoming `p.sessionStatus == .waiting` AND the session already has a visible
   waiting state (queued waiting item OR currently displayed), upsert to refresh
   but skip toast/timer. → verify: coordinator unit tests with a fake ToastPanel:
   (a) first waiting toasts; (b) second waiting refreshes without a second toast
   (AC6); (c) completed after waiting toasts normally and flips status (AC5,
   coordinator half).

### Phase D — rendering (R5, manual verify)
8. `Identity/ReminderPalette.swift`: add an `amber` accent constant + helper. Do
   NOT change the palette array / `paletteCount`. → verify: `swift build`; a tiny
   unit test on any pure status->accent mapping if one is factored.
9. `Panels/TabStripPanel.swift` (`EdgeTabView`): amber breathing border for
   `status == .waiting`; completed unchanged.
10. `Panels/ToastPanel.swift`: mirror the amber accent for a waiting toast; thread
    `status` through the show call. → verify: build + run, drive manually (AC7).

### Phase E — installer (R7)
11. `Hook/HookInstaller.swift`: add `matcher` param to
    `settingsByAddingHook`; tighten the Stop marker to exclude
    `--event notification`; register the Notification hook (event `Notification`,
    command `node "<path>" --event notification`, matcher `permission_prompt`);
    extend `uninstall()` to remove it. → verify: unit tests — add/idempotent/
    remove/coexist for Notification, and Stop untouched by Notification ops (AC8).

### Phase F — full verification
12. `swift build` and `swift test` clean (AC9). Then `make install` (or
    `swift build -c release` + run) and manually verify amber waiting tabs, no
    repeat toast, waiting->completed flip, click-to-jump (AC3, AC7).

## Validation commands

```bash
swift build
swift test
swift test --filter NotifyPayloadTests
swift test --filter ReminderStoreTests
swift test --filter HookInstallerTests
# JS: use existing JS test harness if present, else `node --test Resources/…`
# Manual socket smoke test: python AF_UNIX client from CLAUDE.md
```

## Risky files / rollback points

- `Resources/mate-notify.js` — dual-mode script; a bug here can drop Stop
  notifications for everyone. Keep Stop mode byte-for-byte equivalent when no
  `--event` arg; land Phase A+B behind tests before touching the installer.
- `Hook/HookInstaller.swift` — writes real `~/.claude/settings.json`. Marker
  disambiguation between Stop and Notification is the trap (both use
  mate-notify.js). Unit-test cross-deletion before running `install()` for real.
  Rollback: menu uninstall + git revert.
- `ReminderCoordinator.present` — the no-repeat-toast guard must not regress the
  existing "demote current toast when a newcomer arrives" logic.

## Rollback

Each phase is independently revertible. The wire field (Phase A) is backward
compatible, so partial landing is safe. Full rollback = revert commits +
menu-driven `uninstall()` to clean settings.json.
