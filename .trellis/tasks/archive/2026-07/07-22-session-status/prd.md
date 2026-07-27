# PRD: Session waiting-vs-completed status

## Goal

Let a glance at the tab strip tell "this session is waiting for me to act" apart
from "this session finished normally". Today every tab means the same thing:
the Stop hook fired. This is the plan's (`next-plan.md` #1) first step from a
passive reminder toward an attention scheduler for people juggling many
concurrent Claude sessions.

## User value

The urgency of "Claude is blocked waiting for my permission/input" is very
different from "Claude finished, look when you can". Collapsing both into one
tab hides the signal the user most needs when watching N sessions.

## Confirmed facts (from code)

- Stop hook `mate-notify.js` -> socket -> toast -> queued tab = "completed".
- SessionStart hook `mate-session-start.js` -> `/color` injection only, no tab.
- `NotifyPayload` carries an optional `type` field (`"session_start"` vs absent =
  Stop); adding a status field is backward compatible.
- Tab background is the project color (`colorIndex` + `lightenLevel`); glyph is a
  home icon (main line) or the branch initial. Status must NOT overwrite the
  project color — it can only be an additional overlay.
- `ReminderPhase` is `.toasting(token:)` / `.queued`; dedup is by session UUID.
  Status is orthogonal to phase.
- `HookInstaller` is parameterized by `event` + `marker`, so registering one more
  hook event is cheap and already unit-test-shaped.
- `ReminderCoordinator` already probes iTerm2 findability off-main before
  presenting, and suppresses/replaces per-session via dedup.
- `Notification` hook input includes `notification_type`, `session_id`, `cwd`,
  `message`, `details.tool_name` (verified via Claude Code docs). `matcher`
  filters by `notification_type` (pipe-separated list; `""` = all).

## Risks to verify during implementation

- `ITERM_SESSION_ID` / `CLAUDE_CODE_ENTRYPOINT` are not *documented* for the
  Notification hook (they are inherited from the terminal process, so almost
  certainly present, but must be confirmed empirically). If `ITERM_SESSION_ID` is
  absent, T1 dedup falls back to `session_id` then `cwd`, same as today's Stop
  path — verify this path works before relying on it.
- The idle-timeout duration is undocumented; irrelevant here because idle is
  ignored (R2), but noted so a future wait-duration feature does not assume it.

## Requirements

### R1 — Two triggers both map to "waiting"
Both surface a session as **waiting** (needs the user to act); different
situations, both expected by the user:
- **T1 — Notification hook (permission only)**: Claude Code's `Notification`
  event, limited to the tool-permission-request case. The idle-prompt-timeout
  case is explicitly ignored (see R2).
- **T2 — Stop-with-question**: the Stop hook fires and Claude's last message is a
  question — detected by the conservative heuristic in R3.

A Stop whose last message is not a question = **completed** (today's behavior,
unchanged).

### R2 — Only permission_prompt notifications count
The `Notification` hook payload carries an authoritative `notification_type`
field (verified: `permission_prompt`, `idle_prompt`, `auth_success`,
`elicitation_*`, `agent_*`). Only `notification_type == "permission_prompt"`
sets "waiting"; every other type (notably `idle_prompt`, which fires after a Stop
when a completed tab already exists) is ignored — no text matching on `message`.
Re-flagging a finished session as blocked is a false positive, the plan's top
failure mode. "You've ignored this a while" belongs to the separate
wait-duration feature (plan #2), not here. The hook is registered with
`matcher: "permission_prompt"` so idle/other types do not even reach the script;
the script re-checks `notification_type` defensively.

### R3 — Conservative waiting detection for T2
A Stop is "waiting" if EITHER of these holds on the trimmed
`last_assistant_message`; otherwise "completed". No keyword lists, no LLM.
Bias stays "prefer misses over false alarms".

- **(a) trailing question mark**: the last non-whitespace character is `?` or
  full-width `？`.
- **(b) trailing numbered-choice menu**: the message ends on a
  sequentially-numbered option list — the *final non-empty line* matches
  `^\s*\d+[.)]\s+\S`, and the numbered lines (matching the same pattern) start
  at `1` and increase by `1` for at least 2 items. This catches Claude's
  plain-text "pick 1–N" menus (see the reference screenshot: options `1.`…`5.`,
  the last being a numbered item). Gated on the menu being the tail of the
  message so a normal answer that merely *contains* a numbered list mid-body
  (and ends in prose) does not trip it.

Rule (b) is a deliberate, bounded loosening of the original "trailing `?` only"
guardrail, accepted because the plain-text choice menu is the exact scenario the
user needs surfaced and no dedicated hook signal exists for it (Claude Code has
no `interactive_choice` notification type; `idle_prompt` is rejected — see R2).
The `AskUserQuestion`-tool menu (turn not stopped, no notification) remains an
uncovered gap, out of scope here.

### R4 — Presentation: reuse toast->tab, no repeat toast per session
A waiting event flows through the existing toast (waiting-styled) -> queued tab
path. But if the session already shows a waiting toast or waiting tab, a
subsequent T1 notification only refreshes the existing tab and does NOT re-toast,
so a permission storm cannot spam the screen. A completed Stop always follows
normal toast behavior (a genuine waiting->completed transition is a real state
change worth surfacing).

### R5 — Visual encoding on the tab
- **Waiting**: a bright-white breathing glow around the tab — a crisp white
  border plus an outer glow whose opacity and radius pulse continuously. Project
  color fill and glyph are unchanged.
- **Completed**: exactly today's appearance (no glow).
- The waiting-styled toast mirrors the same white accent (border) so the toast
  and its resulting tab read as one thing.
- (Decision update: the accent was changed from amber to bright white per user
  request during GUI review; a single `ReminderPalette.waitingAccent` constant
  is the source for both tab and toast.)

### R6 — State transitions (per session, deduped by session UUID)
- T1 permission / T2 question -> tab shown as **waiting**.
- A later Stop with no question -> same tab flips to **completed** (amber clears).
- A later T1/T2 while already waiting -> stays waiting, tab refreshed, no re-toast
  (R4).
- Clicking a waiting tab jumps to the pane and removes it (same as completed).
- Non-findable / non-iTerm2 sessions keep today's behavior (dismiss-only tab or
  desktop-notification fallback), carrying the waiting status where a tab shows.

### R7 — Installation & status light
The new `Notification` hook is installed by `HookInstaller` alongside the Stop
and SessionStart hooks (same copy-to-App-Support + settings.json append,
idempotent, own marker). Uninstall removes it too. The menu-bar hook status
light's "installed" definition stays anchored to the core Stop hook (so existing
users are not shown as broken); the Notification hook rides along on install.

## Acceptance criteria

- [ ] AC1 (R1/T2 completed): a Stop whose last message does not end in `?`
  produces a normal **completed** tab — no amber. (Unit test on the JS status
  classifier + Swift status mapping.)
- [ ] AC2 (R3/T2 waiting): a Stop whose trimmed last message ends in `?` or `？`
  produces a **waiting** tab. So does one ending on a sequential numbered-choice
  menu (final non-empty line `^\s*\d+[.)]\s+\S`, numbers `1..k`, k≥2). Messages
  ending in `.`/`!`/plain prose — including ones that merely contain a numbered
  list mid-body — do not. (Unit test the classifier across cases incl. trailing
  whitespace/newlines, the reference-screenshot menu, and a mid-body list.)
- [ ] AC3 (R1/T1): a permission-type `Notification` event produces a **waiting**
  tab for the owning iTerm2 session.
- [ ] AC4 (R2): an idle-timeout `Notification` event produces no tab and no state
  change. (Unit test the JS notification classifier: permission -> send, idle ->
  no-op.)
- [ ] AC5 (R6): for one session UUID, waiting -> (Stop, no `?`) flips to completed
  and clears amber; waiting -> click removes the tab. (Store/coordinator unit
  tests.)
- [ ] AC6 (R4): while a session shows a waiting tab, a second permission
  notification refreshes it without emitting a second toast. (Coordinator unit
  test.)
- [ ] AC7 (R5): waiting tabs render the amber border; completed tabs are visually
  unchanged from today. (Manual GUI verification — GUI is not headless-testable.)
- [ ] AC8 (R7): `HookInstaller` add/remove is idempotent and preserves unrelated
  hooks for the `Notification` event, with its own marker. (Pure-function unit
  tests, mirroring existing Stop/SessionStart tests.)
- [ ] AC9: `swift build` and `swift test` pass; backward compatibility — a
  payload with no status field still decodes as completed.

## Out of scope

- Error / crashed state (plan's state 3) — a later increment.
- Running / in-progress (grey) live dashboard (plan's direction 1) — later.
- Wait-duration weighting / escalation (plan #2), including idle-timeout as a
  signal.
- Distinguishing permission-waiting from question-waiting visually (both are one
  amber "waiting" state in this increment).
