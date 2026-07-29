# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## GitHub CLI

Before any `gh` CLI operation, run once to select the personal account that owns this repo:

```bash
gh auth switch --user lorne-luo
```

## What this is

A Swift macOS menu-bar app (`LSUIElement`/`.accessory`, no Dock icon) that is a reminder companion for Claude Code sessions running in iTerm2. When a Claude session finishes, a Node Stop hook sends a payload to the app; the app shows a toast, then queues a reminder tab on the right screen edge (one per iTerm2 session). Hovering a tab shows the full reply; clicking it jumps to the owning iTerm2 pane. Beyond reminders it also color-codes each session (iTerm2 pane background + Claude Code prompt bar `/color`) per git project, and surfaces a usage badge (5h / 7d limits).

## Commands

```bash
swift build                 # debug build
swift build -c release      # release build
swift run -c release        # launch (NOT a bundle: Launch-at-Login is a no-op here)
swift test                  # full Swift suite
swift test --filter ReminderStoreTests               # one test class
swift test --filter ReminderStoreTests/testUpsert... # one test method
node --test 'Tests/js/**/*.test.js'                  # JS hook classifier tests
```

The Swift tests are pure-logic XCTest (no GUI). The JS tests cover `mate-notify.js`'s pure classifiers (`classifyStopStatus`, `eventMode`, `buildQuestionFields`, …). GUI behavior (toast/tab/hover/menu) cannot be verified headless — build + run and drive it manually.

`swift run` starts a bare binary. To exercise the real feature set (Launch at Login via `SMAppService`, hook install, `.app` layout) build and run the **bundle** via the Makefile (this is what you actually run day-to-day):

```bash
make build       # scripts/make-app.sh -> dist/ClaudeItermMate.app (ad-hoc signed)
make run         # build, then open dist/
make install     # build, then install to /Applications (quits any running instance first)
make uninstall   # remove /Applications/ClaudeItermMate.app
make test        # swift test
make release VERSION=1.2.0   # scripts/release.sh: validate tree, push tag, CI builds the dmg
```

### Exercising the socket manually

The app listens on a unix socket at `~/Library/Application Support/ClaudeItermMate/notify.sock`. **`nc -U` does NOT deliver correctly on macOS** — use a Python AF_UNIX client that writes, half-closes, then closes:

```python
import socket, json, time, os
p = os.path.expanduser("~/Library/Application Support/ClaudeItermMate/notify.sock")
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(p)
s.sendall(json.dumps({"session_uuid":"S1","cwd":"/x/proj","title":"[CC] proj",
  "summary":"done","full_message":"done","timestamp":time.time()*1000,
  "repo_root":"/x/proj","branch":"main"}).encode())
s.shutdown(socket.SHUT_WR); s.close()
```

## Architecture

AppKit shell (`main.swift` + `AppDelegate`) hosts SwiftUI views inside borderless, non-activating `NSPanel`s. One-way data flow, each unit small and independently testable. Node hooks feed the app over a unix socket; the app fans out to reminders, pane coloring, and usage:

```
Node Stop hook (Resources/mate-notify.js)                    -> reminder; status: completed | waiting
Node Notification hook (mate-notify.js --event notification) -> reminder; status: waiting (permission_prompt)
Node PreToolUse hook  (mate-notify.js --event ask)           -> reminder; type: question (+ questions[])
Node PostToolUse hook (mate-notify.js --event ask-done)      -> type: resolve (clear the tab)
Node SessionEnd hook  (mate-notify.js --event session-end)   -> type: resolve + end_reason (clear the tab on exit)
Node SessionStart hook (Resources/mate-session-start.js)     -> type: session_start (color the pane)
  --unix socket, one JSON message per connection (close = frame boundary)-->
NotifyServer  -> NotifyPayload.decode  -> ReminderCoordinator.handle
  ├─ session_start -> colorPaneIfNeeded (ItermBgColorAction -> set-pane-bg.py) + usage.probeHudCache
  ├─ resolve       -> ReminderStore.remove (+ ItermBgColorAction.reset when isSessionExit)
  └─ Stop/Notification/ask ->
       colorPaneIfNeeded + injectColorIfNeeded (ItermColorAction /color) + usage.refreshIfStale
       + reconcile (GC color/flag/dead-tab for closed panes via live AppleScript session set)
       -> ReminderStore.upsert -> ToastTimer (8s, pausable) -> toasting -> queued
       -> ToastPanel --fly-in--> TabStripPanel (right edge) --hover--> DetailPanel
Click a tab/toast -> ItermFocusAction (focus / focus+maximize) -> ReminderStore.remove
Double-click a title row (toast or hover detail) -> focus+maximize ALWAYS -> ReminderStore.remove
Answer a question in DetailPanel -> ItermSendTextAction (it2 session send) -> pane
Non-iTerm2 session -> AppDelegate.desktopNotify (osascript) — never a tab
```

**Session coloring** (`Identity/ColorAssigner`, `PaneShade`, `Actions/ItermBgColorAction` +
`ItermColorAction`): each git project maps to one of the 8 palette slots. On SessionStart (and
backfilled on Stop) the iTerm2 **pane background** is set to a dark variant of that hue via the
machine-local `set-pane-bg.py` (iTerm2 Python API — a per-session profile override that never
touches the tty, so a running TUI is unaffected). On the **first genuine Stop** of a session,
`/color <name>` is injected into the prompt bar so the composer color matches (`ItermColorAction`:
ctrl+s stash as its **own** send, awaited with a bounded timeout, then `/color <name>` + `\r`
submit; gated on `isStop`, never on a live permission/question TUI). When Claude Code **exits**
(SessionEnd `reason == "prompt_input_exit"`, what a genuine quit emits — the reason enum is exactly
`clear` | `logout` | `prompt_input_exit` | `other`, verified in the Claude Code 2.1.220 binary;
never `clear`, which keeps Claude alive and is followed by a SessionStart, and `logout` / `other`
stay colored on purpose) the pane background is reset to its profile default and **both**
color memories for that session (`coloredSessions` hex and the `colorInjectedSessions` flag) are
dropped, so a restart in the same still-open pane re-colors the pane *and* re-injects `/color`;
clearing only one would leave pane and prompt bar disagreeing. Both share
the `colorPanes` toggle and the same `ColorAssigner` slot so pane, tab, and prompt bar agree.
`ColorAssigner` is collision-averse (preferred slot = FNV-1a hash mod 8, linear-probe if a different
live repo holds it); worktree siblings share one slot and separate by a darkness step (`PaneShade`),
mirroring how tabs separate them by a lighten step. All gating/dedup (`coloredSessions` by hex,
`colorInjectedSessions` once-per-session) lives in `ReminderCoordinator`.

**AskUserQuestion** (`--event ask` / `ask-done`): a PreToolUse hook (matcher
`AskUserQuestion`) surfaces the question + options as a rich waiting tab
(`ReminderItem.kind == .question`, carrying `NotifyPayload.questions`); both the
DetailPanel and the toast render answer controls (`QuestionAnswerView`:
option buttons, a free-text field, "Chat about this") for a single-question
prompt — the toast stays non-key until the free-text field is clicked
(`onEditingBegan` → `panel.makeKey()`) so it never steals terminal focus on
appearance. Both surfaces scroll their controls as a fallback (`scrolls` flag; the
measuring probe passes `false`) for when the content exceeds the card's cap —
without a `ScrollView` the card clipped its own title row, close button and
Send/Chat controls. An 8-option question measures **689pt** and now fits inside
the toast's 700pt cap without scrolling (it used to be capped at 360). The detail
popup additionally needs
`.id(item.sessionUUID)` on `QuestionAnswerView`, since it reuses one hosting
controller and would otherwise carry typed text / ticked options over to a
*different* session's question. Answering injects keystrokes into the
owning pane via `ItermSendTextAction` (`it2 session send -s <uuid>`); the exact
TUI sequences (single digit selects+submits; free text = "Type something" row +
text + `\r`; multiSelect = digit toggles + right-arrow + Submit) were verified
against the real TUI. AskUserQuestion also fires a generic `permission_prompt`
Notification for the same session, sharing one **`prompt_id`** (verified live) —
the coordinator remembers the prompt ids it has surfaced as questions
(`questionPromptIDs`, a bounded FIFO) and drops the companion waiting event by id,
so it cannot clobber the rich detail. Matching on the id rather than on "a
`.question` item exists in the store" is essential: `handle` runs `reconcile`
**before** `present`, and reconcile GCs items whose session is not in the iTerm2
live set (a closed pane whose Claude process is still alive), which deleted the
question item out from under the old store-state check and let the generic toast
win. That memory is therefore deliberately NOT keyed by session and NOT filtered
in `reconcile` — doing so would drop it for exactly the un-findable sessions this
protects. A genuine permission request carries a *different* `prompt_id` and still
gets through. The store-state check is kept as a fallback for hook scripts
published before `prompt_id` (it still misses once reconcile has GC'd, which
resolves itself on the next app launch when `install()` republishes the scripts).
A PostToolUse `resolve` clears the tab on answer (Stop upsert is the backstop).
Interactive answering is limited to single-question prompts; multi-question
prompts fall back to "Chat about this" (jump).

**Session status** (`Store/SessionStatus.swift`): a `completed`/`waiting` dimension
orthogonal to `phase`. A **waiting** tab (session needs the user to act) renders a
bright-white breathing glow; **completed** looks as before. `mate-notify.js` is
dual-mode: the Stop hook marks `waiting` when the reply ends in `?`/`？` or a
trailing sequential numbered-choice menu (`classifyStopStatus`, conservative);
the `--event notification` mode (registered with matcher `permission_prompt`)
marks `waiting` for permission prompts only. Wire field `status` is optional —
absent/unknown decodes as `completed` (backward compatible).

**Usage badge** (`Usage/UsageService`, `UsageData`, `KeychainReader`): `UsageService`
(`@Observable`, main-actor) owns one `UsageSnapshot` refreshed non-blocking and rate-limited
(≥60 s, single-flight guard) on each reminder. Source is chosen by `hudCacheAvailable` (probed on
session_start): read claude-hud's local `.usage-cache.json` when present, else self-fetch from the
OAuth usage API (`GET api.anthropic.com/api/oauth/usage`) using the bearer token read from the
Keychain via `/usr/bin/security` (`KeychainReader`, `Process` with absolute path + arg array — no
shell). All blocking IO (disk read, `security` fork, network) runs off the main actor. The snapshot
renders as two thin meters (`UsageBadgeView`: a 30×3 Capsule track per window) in the toast title row
and the detail header — bar length is the utilization, tint is `UsageLevel` (green <50%, amber <80%,
red above), and a non-zero utilization always draws at least a visible dot (`fillWidth`). The detail
header adds the numeric percent; the toast omits it so the meters never squeeze the project · branch
title. `badgeText` survives as the meters' VoiceOver label.

Key pieces (all under `Sources/ClaudeItermMate/`):

- **Server/NotifyServer** — POSIX `AF_UNIX` + `DispatchSource` listener (NOT Network.framework `NWListener`). One message per connection; the listener FD is closed in the source's cancel handler (on the serial queue) to avoid a close-during-accept race. Single-instance guard: if the socket is already connectable, the second instance quits.
- **Server/NotifyPayload** — `Codable` model; `decode` validates and enforces a 1 MB cap. `type` selects the branch (`session_start` / `resolve` / reminder); `isStop`, `isQuestion`, `isSessionStart`, `isResolve`, `isSessionExit` are derived. Git fields (`repo_root`, `branch`, `is_worktree`), `status`, `prompt_id` and `end_reason` are optional for backward compatibility; `sessionStatus` maps the wire string to `SessionStatus`. `end_reason` is SessionEnd's `reason` forwarded verbatim on a `resolve`; `isSessionExit` is the app-side policy (only `prompt_input_exit`, the reason a genuine quit emits) that drives the pane-background reset — an `ask-done` resolve and any pre-feature resolve carry no reason and never reset. `prompt_id` is Claude Code's per-turn id, shared by an AskUserQuestion PreToolUse and the `permission_prompt` Notification it also fires — see the AskUserQuestion note above.
- **Store/ReminderStore** — `@Observable` single source of truth. `ReminderItem.phase` is `.toasting(token:)` or `.queued`; `.status` is `.completed`/`.waiting`; `.kind` is `.plain`/`.question`. The tab strip renders only `.queued`. Dedup is by iTerm2 session UUID. Owns the shared `ColorAssigner` and assigns `colorIndex` + per-project `lightenLevel` (concurrent same-directory sessions get incremental lighten steps) at upsert. `refreshContent` updates content in place without touching phase/token/status (no-repeat-toast path). Timer-free and synchronous so it is fully unit-testable.
- **ReminderCoordinator** — owns the `ToastTimer`s and the toasting→queued transition; a per-toast token prevents an older session's expiring timer from hiding a newer session's visible toast. Also routes `session_start`/`resolve`, drives pane coloring + `/color` injection + usage refresh, plays the reminder sound once per genuinely-presented toast, and emits the non-iTerm2 desktop notification. A waiting session already showing a waiting tab/toast is refreshed in place (no repeat toast — guards a permission storm). On each reminder it reuses the off-main iTerm2 probe (now the full live-session set, not just a `canFind`) to `reconcile`: any session absent from the live set has its color hex, once-per-session `/color` flag, and dead tab GC'd — the lazy way pane closure is detected. Reconcile is skipped when the live set is unknown (`liveSessionIDs() == nil`), so a transient enumeration failure never wipes live sessions.
- **ToastTimer** — a pausable one-shot countdown (default 8 s). Hovering the toast pauses it (user is reading); leaving resumes from the banked remaining time, not a fresh full term.
- **AppSettings** — `UserDefaults`-backed toggles mirrored in the menu bar: `showNonIterm`, `colorPanes`, `showTabStrip`, `playSound` (all default true). `ReminderCoordinator` reads them through injected closures so its logic stays testable.
- **Identity/ReminderIdentity** — pure derivation from a payload: `key` = repoRoot (else cwd), `project` = basename, `worktreeGlyph` (branch last-segment initial, or `●` for main/none), `colorIndex` = stable FNV-1a hash of key mod `paletteCount` (8). `locationLabel` picks the branch name or the shorter of relative/absolute worktree path.
- **Identity/ColorAssigner** — in-memory, collision-averse project→slot authority shared with the tab renderer and `/color` injection; preferred slot is the FNV-1a hash, linear-probed to a free slot when possible. Pure/synchronous/testable.
- **Identity/PaneShade** — worktree darkness level (0 = mainline, 1…levels-1 hashed from branch) for pane backgrounds — the dark-space analog of the tab lighten level.
- **Identity/ReminderPalette** — 8-color categorical palette; `names` are Claude Code's 8 `/color` **hues** — the full `/color` set is `red|blue|green|yellow|purple|orange|pink|cyan|default`, and `default` is deliberately excluded (it clears the color rather than being a hue). Order is a stable contract — reordering reassigns every project. Tabs render bright `rgb`, lightened per worktree level; pane backgrounds render dark variants solved to a fixed target luminance (`backgroundHex`); glyph foreground flips black/white by luminance. `waitingAccent` (white) is deliberately NOT a slot so it never shifts the `/color` mapping.
- **Usage/UsageService + UsageData + UsageBadgeView + KeychainReader** — the usage badge subsystem (see above). `UsageSnapshot.decode` (wire), `decodeHudCache` (claude-hud file), `UsageLevel` (tint thresholds) and `UsageBadgeView.fillWidth` are pure/testable; `KeychainReader.parseAccessToken` enforces `expiresAt`.
- **Panels/PanelFactory** — the shared `NSPanel` recipe: borderless + `.nonactivatingPanel`, floating, clear background, `canJoinAllSpaces`/`fullScreenAuxiliary`, `canBecomeKey` only when interaction is needed. Returns a `KeyablePanel` whose `allowsKey`/`allowsMain` stay **mutable**: DetailPanel reuses one panel across items and re-applies `allowsMain` per show, since only a question item may become main (frozen-at-construction meant a question shown after a plain reminder could never focus its answer field). ToastPanel / TabStripPanel / DetailPanel / InfoToastPanel build on it. DetailPanel measures content to size itself and hosts the usage meters + `QuestionAnswerView`.
- **Panels/ToastPanel** — the toast's height follows its content: an offscreen `NSHostingView` probe measures the card at `width` and clamps to `[56, 700]` (`maxHeight` is a last-resort anti-off-screen cap, since `EdgeGeometry.toastFrame` does no clamping of its own; 700 + the 12pt margin fits the smallest supported display). One measure-and-clamp path serves both a question (an 8-option one measures 689pt, so it no longer scrolls) and a plain reply. A plain toast whose message is truncated also gets a **chevron** under the body that grows the card downward to the full text — `toastFrame` derives y from `maxY - margin - height`, so the top edge stays put and it grows down; expanded content gets a `ScrollView` because it can still exceed the cap. Whether to offer the chevron is decided by *measuring* (`needsExpandToggle(collapsed:expanded:)`), never by estimating wrapped line counts — at 440pt a CJK glyph is ~2× a latin one, so counting characters is unreliable. `shownItem`/`shownVisible`/`shownShowsToggle` are cached only so the toggle can re-measure and re-frame; they are cleared on dismiss/hide.
- **Actions/ItermFocusAction** — jumps to the pane. Maximize-on-click (menu toggle, `UserDefaults`) chooses between the machine-local `~/.claude/scripts/iterm-focus-pane.py` (focus + maximize) and the `it2` CLI (`app activate` + `session focus`, focus only). Also exposes `resolveIt2()` / `it2Process(...)` reused by the other `it2` actions. `plan()` is pure/tested.
- **Actions/ItermSessionLookup** — enumerates live sessions over **AppleScript** (`osascript -e 'tell application "iTerm2" to get id of every session of every tab of every window'`, guarded by `is running` so it never launches iTerm2) to answer "does this session still exist?" **Not** `it2 session list`: with a tab in "Maximize Active Pane" the iTerm2 Python API exposes only the maximized session, which made every other session un-findable (click → toast vanished without jumping, no tab, and reconcile GC'd the live tabs). A non-findable reminder only toasts and never becomes a dead, un-jumpable tab. `liveSessionIDs()` returns the full live set (or `nil` when the query fails) and doubles as the coordinator's reconcile input; the `ItermSessionProbe` protocol declares it with an extension default of `nil` so stubs skip GC. `parseSessionIDs` is pure/tested.
- **Actions/ItermBgColorAction** — sets the pane background by spawning `set-pane-bg.py <uuid> <RRGGBB>` (iTerm2 Python API). `reset(sessionUUID:)` spawns the same script with the `default` sentinel instead of a hex, which restores the pane's underlying profile background (`Profile.original_guid` → `Profile.async_get` → `LocalWriteOnlyProfile`; iTerm2 2.20 has no "drop the override" call, so the override is re-set to the base value). An older installed script cannot parse the sentinel as hex: it raises an uncaught ValueError and prints a traceback to the app's inherited stderr, but the pane outcome is still correct (background unchanged, keeps its project color) — degraded, never broken. Not to be confused with `/color default`, the hue `ReminderPalette` excludes. Gated on the script being present. `arguments(...)` / `resetArguments(...)` are pure/tested.
- **Actions/ItermColorAction** — injects `/color <name>` via **two** `it2 session send` calls: the ctrl+s stash alone, awaited, then the slash command + `\r` submit (see coloring note). The wait is the point — two concurrent `it2` processes could let `/color` land before the stash and mangle the composer — but it is **bounded** (`sendTimeout`, 5 s, via `terminationHandler` + `DispatchSemaphore.wait(timeout:)`, then `terminate()`): a hung `it2` must not park a thread on the shared utility queue forever. Safe to block at all because `AppDelegate` calls `inject` on that utility queue. A failed or timed-out stash still proceeds to the `/color` send. `stashArguments(...)` / `arguments(...)` are pure/tested.
- **Actions/ItermSendTextAction** — answers an AskUserQuestion by injecting keystrokes into the owning pane via `it2 session send -s <uuid> <fragment>`. `injectionSequence(_:optionCount:)` and `arguments(...)` are pure/tested; sequences verified against the real TUI. Gated on `focusable`.
- **Hook/HookStatus + Hook/HookInstaller** — the menu status light. HookStatus reads `~/.claude/settings.json`; HookInstaller copies the two bundled scripts (`mate-notify.js`, `mate-session-start.js`) to App Support and appends six hooks — Stop (`mate-notify.js`), SessionStart (`mate-session-start.js`), Notification (`mate-notify.js --event notification`, matcher `permission_prompt`), PreToolUse (`--event ask`, matcher `AskUserQuestion`), PostToolUse (`--event ask-done`, matcher `AskUserQuestion`), SessionEnd (`--event session-end`, clears the tab and forwards `end_reason` on session exit) — each idempotent, append-only, preserving other hooks. Markers are per-event, so the five hooks sharing `mate-notify.js` never cross-delete. Scripts are published atomically (temp + swap) since `install()` re-runs on launch. HookStatus still probes only the Stop hook as the single opt-in signal. **Upgrade path**: `AppDelegate` re-runs the idempotent `install()` on launch when the hook is already installed, so new bundled hooks/scripts propagate to existing users without a manual remove+reinstall (the menu only offers Install when *not* installed).
- **MenuBar/MenuBarController** — `NSMenuDelegate`; rebuilds on `menuNeedsUpdate` so the hook light + toggles reflect live state. `menu.autoenablesItems = false` is required — otherwise AppKit re-enables items by target and the "disabled until installed" state silently breaks.

### Bundled resources (`Sources/ClaudeItermMate/Resources/`)

- **Loaded at runtime via `Bundle.module`** (declared in `Package.swift` `resources`): `mate-notify.js`, `mate-session-start.js`. These are the canonical hook scripts the installer copies to App Support.
- **Reference-only, excluded from the SwiftPM build** (`Package.swift` `exclude`): `set-pane-bg.py` (pane background, spawned by `ItermBgColorAction` from `~/.claude/scripts/`), `open-vscode.py`, `open-zed.py` (iTerm2 hotkey scripts that open the session's cwd in an editor). Like `iterm-focus-pane.py`, these are installed to `~/.claude/scripts/` on the machine, not shipped in the bundle.

## Constraints

- macOS 14+, Swift tools 5.9, **no external Swift dependencies**, POSIX sockets only. Bundled hook scripts are self-contained Node (built-ins only); machine-local scripts are Python (iTerm2 API).
- Never modify `~/.claude/scripts/desktop-notify.js`. The hook installer *does* write `~/.claude/settings.json` (that is its purpose) but tests must never touch the real file — inject temp paths / test JSON into the pure functions.

## Gotchas

- **Paths with spaces**: the install path is `~/Library/Application Support/...` (a space). Any command written for a shell/`node`, and any path parsed out of a command, must handle the space — quote when writing (`node "<path>"`), and extract the whole path (not a whitespace-split token) when reading. Two separate bugs in this repo came from this; both have regression tests.
- **`\r` vs `\n` for TUI submit**: Claude Code's raw-mode TUI submits on `\r` (0x0D), NOT `\n` (0x0A). `it2 session run` appends `\n` and leaves the command unsubmitted — the `it2` actions use `session send` with an explicit trailing `\r` instead (verified live).
- **A measuring probe must render exactly what the live view renders**: `ToastPanel.fittingHeight` builds an offscreen `ToastView` to size the panel, so every input that affects height has to be passed in. It was omitting `usage` (the meters make the title row taller) and `showsExpandToggle` (the chevron's row is ~16pt — almost exactly one line), and each shortfall silently clipped the message's **last line**. Deciding whether to show the chevron therefore takes two toggle-less measurements (a fair comparison) before a third measures the final height *with* it. `.fixedSize(horizontal: false, vertical: true)` is NOT needed here despite `InfoToastView` having it — measured identical with and without, including wrapped 2760pt content, because `.frame(maxWidth: .infinity)` already constrains the width.
- **Swap `rootView`, never rebuild the host**: `TabStripPanel` and `DetailPanel` keep their `FirstMouseHostingView` / `NSHostingController` and assign a fresh `rootView` on each render. Replacing the host discards the hosted SwiftUI `@State` — every tab's hover highlight and the waiting breathing animation restarted on each store mutation, and DetailPanel allocated a controller per hover.
- **Tab strip controls are `Button`s, not `onTapGesture`**: tabs render only a glyph, so the Button carries the spelled-out `project · branch — waiting` label (tooltip + VoiceOver) and the glyph itself is `accessibilityHidden`. The toast card cannot be a Button (it embeds buttons and its title row needs a 2-count gesture), so it declares `accessibilityElement(children: .contain)` + both jump actions explicitly.
- **Maximized panes hide sessions from the iTerm2 Python API**: while a tab is in "Maximize Active Pane", `tab.sessions` (and therefore `it2 session list`) reports ONLY the maximized session — verified live: 6 sessions vs 1. `app.get_session_by_id` still resolves the hidden ones, so *jumping* works; only enumeration is affected. Since maximize-on-click is the default, one jump used to make every subsequent session un-findable. Enumerate via AppleScript (`ItermSessionLookup`), never via the Python API.
- **SourceKit false positives**: the editor often reports `Cannot find type '...'` / `No such module 'XCTest'` for cross-file symbols because it indexes files outside the SwiftPM build graph. These are noise — trust `swift build` / `swift test`, not the inline diagnostics.
