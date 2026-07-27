# Design: Session waiting-vs-completed status

## Overview

Add an orthogonal **status** dimension (`completed` | `waiting`) that flows from
two hook triggers through the existing socket -> payload -> store -> coordinator
-> tab pipeline, and renders as an amber breathing border on waiting tabs. No new
transport, no new panel; every piece extends an existing seam.

## Data flow (unchanged spine, new field)

```
Stop hook (mate-notify.js)        --status: waiting|completed (trailing "?")-->
Notification hook (mate-notify.js --event notification, matcher permission_prompt)
                                  --status: waiting-->
  unix socket --> NotifyServer --> NotifyPayload.decode (new `status` field)
    --> ReminderCoordinator.handle --> ReminderStore.upsert (carries status)
      --> ToastPanel (amber accent) / TabStripPanel (amber border)
```

## Component changes

### 1. JS hook script — reuse `mate-notify.js` for both events

Rather than a second script, extend `mate-notify.js` with an event mode so the
socket/git/fallback logic stays single-sourced. Selected by an explicit CLI arg
so behavior is deterministic and testable:

- `node mate-notify.js` (no arg) — **Stop** mode (today's behavior) plus: compute
  `status`. `status = "waiting"` iff the trimmed `last_assistant_message` either
  (a) ends in `?`/`？`, or (b) ends on a sequential numbered-choice menu — final
  non-empty line matches `^\s*\d+[.)]\s+\S` and the numbered lines run `1..k`
  (k≥2). Else `"completed"`. Keep this in the pure, unit-tested
  `classifyStopStatus(msg)` (see R3 for the rationale and false-positive gating).
  Add `status` to the payload fields.
- `node mate-notify.js --event notification` — **Notification** mode. Read
  `notification_type` from stdin JSON; if it is not `permission_prompt`, exit
  silently (defensive — matcher should already filter). Otherwise build a payload
  with `status: "waiting"`, `summary`/`title` derived from `cwd` (and
  `details.tool_name` if present, e.g. "waiting: Bash"), `full_message` = the
  notification `message`. Reuse the same iTerm2/session-UUID derivation, git
  enrichment, socket send, and — importantly — **no desktop-notification
  fallback** in notification mode (a missed permission ping must not spam
  notifications; if the app is down, stay silent, matching mate-session-start.js).

Extract the shared `gitInfo`, session-UUID derivation, and socket-send into
small functions so both modes call them. Keep a pure `classifyStopStatus(msg)`
and `shouldSendNotification(input)` for unit testing (Node's built-in
`node:test`, run via the existing test harness if present, else documented
manual invocation — see implement.md).

Env-var note: both modes read `ITERM_SESSION_ID` / `CLAUDE_CODE_ENTRYPOINT` from
`process.env`, inherited from the terminal. Notification mode uses the same
`focusable`/`sessionUUID` fallback chain as Stop mode.

### 2. `NotifyPayload` — add optional `status`

- New `let status: String?` with `CodingKey` `status`; `decodeIfPresent`.
- Add a computed `var sessionStatus: SessionStatus` mapping
  `"waiting" -> .waiting`, anything else (incl. nil) -> `.completed`. This keeps
  old payloads (no field) decoding as completed (AC9).
- Define `enum SessionStatus: Equatable { case completed, waiting }` (own file
  `Store/SessionStatus.swift` or alongside `ReminderPhase`).

### 3. `ReminderStore` / `ReminderItem` — carry status

- Add `var status: SessionStatus` to `ReminderItem`.
- `upsert` sets `status: p.sessionStatus`. Because dedup removes the prior item
  for the session and inserts the new one, a later payload naturally replaces the
  status (waiting -> completed on a no-question Stop; R6). No extra transition
  code in the store — the store stays synchronous/testable.
- `status` is independent of `phase`; the strip renders `.queued` items and reads
  `status` for styling.

### 4. `ReminderCoordinator` — no-repeat-toast for a session already waiting (R4)

`present(_:findable:)` currently always shows a toast. Add: before toasting,
check whether the same session already has a **visible waiting state** — i.e. an
existing store item for `p.sessionUUID` whose `status == .waiting` AND
(`phase == .queued` OR it is the currently `displayed` toast) — and the incoming
payload is also `.waiting`. If so, upsert (to refresh) but skip the toast:

- still call `store.upsert(p)` so the tab refreshes and stays waiting,
- do NOT create/show a toast or a timer for it,
- leave any currently displayed toast untouched.

A completed payload, or the first waiting for a session, toasts normally. This is
the only new branch; keep it small and unit-tested via a fake `ToastPanel`.

Order of checks in `handle`: `isSessionStart` (unchanged) -> usage refresh ->
focusable branch (unchanged) -> probe -> `present`. The no-repeat logic lives in
`present` (or a guard just before it) where both the payload and current store
state are available on main.

### 5. Tab & toast rendering — bright-white breathing glow (R5)

`EdgeTabView` (TabStripPanel.swift): when `item.status == .waiting`, overlay a
dedicated `WaitingGlow` subview that draws a bright-white border + outer glow and
pulses continuously.

- `ReminderPalette.waitingAccent` is a single non-palette accent constant
  (`Color.white`) used by both tab and toast; do NOT touch the categorical
  palette array (keep `paletteCount` invariant).
- `WaitingGlow`: a `strokeBorder(waitingAccent, lineWidth: ~1.5)` driven by an
  infinite `phaseAnimator([0,1]) { … } animation: { .easeInOut(duration: ~1.25) }`
  that interpolates the border opacity and a white `shadow`'s opacity/radius.
  Because the overlay is only present while waiting, the animator starts and
  stops automatically as the status flips — no `@State`/`onAppear`/`onChange`
  bookkeeping, and the completed→waiting-while-visible case animates for free.
  Requires macOS 14+ (`phaseAnimator`), which is the deployment target.
- Keep the project-color fill and glyph untouched (constraint from PRD).
- `ToastPanel`: mirror the same white accent (border) for a waiting toast so
  toast and tab read as one; `item.status` is already threaded through the toast.

GUI cannot be headless-tested (AC7 is manual). Styling logic is kept thin; the
status→visual mapping is a plain `if isWaiting` with the shared accent constant.

### 6. `HookInstaller` — register the Notification hook (R7)

- Add a third install triple using the SAME script file (`mate-notify.js`)
  registered under event `Notification` with a distinct **marker** and a
  **matcher**. Problem: the current `settingsByAddingHook` markers on the command
  string, and both Stop and Notification would use the same `mate-notify.js`
  command — the marker would collide. Fix: differentiate the Notification command
  (`node "<path>" --event notification`) so its command string is distinct;
  marker = `mate-notify.js --event notification`, Stop marker stays
  `mate-notify.js` but must be matched more precisely (e.g. the Stop command has
  no `--event`). Simplest robust approach: give `settingsByAddingHook`/
  `settingsByRemovingHook` a `matcher` param (default `""`) and match on the full
  command string; Stop uses marker `mate-notify.js"` (trailing quote, no
  `--event`) — but that is brittle.
  **Chosen approach:** match Stop by the exact command it installs and
  Notification by its exact command (both include the quoted path; Notification
  additionally ends with `--event notification`). Update the Stop marker check to
  require the command NOT contain `--event notification`. Add unit tests for: add
  Notification when absent, idempotent re-add, remove only Notification, Stop and
  Notification coexisting without cross-deletion.
- `settingsByAddingHook` gains a `matcher: String = ""` param, written into the
  group as `"matcher": matcher`; Notification passes `"permission_prompt"`.
- `install()` writes all three; `uninstall()` removes all three (extend the
  existing remove calls with the Notification event + marker).
- Hook status light (`HookStatus`/`MenuBarController`): keep "installed" anchored
  to the Stop hook so existing users are unaffected; the Notification hook rides
  along. (No change required to HookStatus for green; optionally note presence.)

## Contracts

- Payload JSON gains one optional key: `"status": "waiting" | "completed"`.
  Absent = completed. This is the only wire change; fully backward compatible.
- `matcher` for the Notification group is `"permission_prompt"`.

## Compatibility / rollback

- Old hook scripts (no `status`) -> payload decodes as completed; app behaves
  exactly as today. New app + old payloads: fine. New payloads + old app: the old
  app ignores unknown keys (JSONDecoder), still shows a completed tab.
- Rollback = revert commits; `uninstall()` (menu) cleans settings.json. Because
  the Notification hook is append-only and idempotent, a partial state is safe.

## Trade-offs / decisions

- **Reuse mate-notify.js over a new script**: one source of truth for socket/git
  logic; the `--event` arg keeps modes explicit and testable. Cost: one file does
  two jobs (mitigated by extracted functions + the arg switch).
- **Discriminate by `notification_type`, not message text**: authoritative, locale
  -proof, matcher can pre-filter. (Corrects the initial plan assumption of text
  matching.)
- **Status orthogonal to phase**: avoids expanding the phase enum combinatorially
  and keeps the store's transition-free dedup model intact.
- **Amber as a non-palette constant**: preserves `paletteCount` and the
  color-sync contract with `/color`.
```
