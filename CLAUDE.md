# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## GitHub CLI

Before any `gh` CLI operation, run once to select the personal account that owns this repo:

```bash
gh auth switch --user lorne-luo
```

## What this is

A Swift macOS menu-bar app (`LSUIElement`/`.accessory`, no Dock icon) that is a reminder companion for Claude Code sessions running in iTerm2. When a Claude session finishes, a Node Stop hook sends a payload to the app; the app shows a toast, then queues a reminder tab on the right screen edge (one per iTerm2 session). Hovering a tab shows the full reply; clicking it jumps to the owning iTerm2 pane.

## Commands

```bash
swift build                 # debug build
swift build -c release      # release build (what you run)
swift run -c release        # launch the app
swift test                  # full test suite
swift test --filter ReminderStoreTests               # one test class
swift test --filter ReminderStoreTests/testUpsert... # one test method
```

Tests are pure-logic XCTest (no GUI). GUI behavior (toast/tab/hover/menu) cannot be verified headless — build + run and drive it manually.

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

AppKit shell (`main.swift` + `AppDelegate`) hosts SwiftUI views inside borderless, non-activating `NSPanel`s. One-way data flow, each unit small and independently testable:

```
Node Stop hook (Resources/mate-notify.js)                  -> status: completed | waiting
Node Notification hook (mate-notify.js --event notification) -> status: waiting (permission_prompt)
  --unix socket, one JSON message per connection (close = frame boundary)-->
NotifyServer  -> NotifyPayload.decode  -> ReminderStore.upsert
  -> ReminderCoordinator (owns the toast timer; toasting -> queued)
  -> ToastPanel (4s) --fly-in--> TabStripPanel (right edge) --hover--> DetailPanel
Click a tab -> ItermFocusAction (focus / focus+maximize) -> ReminderStore.remove
```

**Session status** (`Store/SessionStatus.swift`): a `completed`/`waiting` dimension
orthogonal to `phase`. A **waiting** tab (session needs the user to act) renders a
bright-white breathing glow; **completed** looks as before. `mate-notify.js` is
dual-mode: the Stop hook marks `waiting` when the reply ends in `?`/`？` or a
trailing sequential numbered-choice menu (`classifyStopStatus`, conservative);
the `--event notification` mode (registered with matcher `permission_prompt`)
marks `waiting` for permission prompts only. Wire field `status` is optional —
absent/unknown decodes as `completed` (backward compatible).

Key pieces (all under `Sources/ClaudeItermMate/`):

- **Server/NotifyServer** — POSIX `AF_UNIX` + `DispatchSource` listener (NOT Network.framework `NWListener`). One message per connection; the listener FD is closed in the source's cancel handler (on the serial queue) to avoid a close-during-accept race. Single-instance guard: if the socket is already connectable, the second instance quits.
- **Server/NotifyPayload** — `Codable` model; `decode` validates and enforces a 1 MB cap. New git fields (`repo_root`, `branch`, `is_worktree`) and `status` are optional for backward compatibility; `sessionStatus` maps the wire string to `SessionStatus`.
- **Store/ReminderStore** — `@Observable` single source of truth. `ReminderItem.phase` is `.toasting(token:)` or `.queued`; `ReminderItem.status` is `.completed`/`.waiting` (orthogonal to phase). The tab strip renders only `.queued`. Dedup is by iTerm2 session UUID. `refreshContent` updates an item's content in place without touching phase/token/status (used by the no-repeat-toast path). Stays timer-free and synchronous so it is fully unit-testable.
- **ReminderCoordinator** — owns the toast timer and the toasting→queued transition; a per-toast token prevents an older session's expiring timer from hiding a newer session's visible toast. A waiting session that already shows a waiting tab/toast is refreshed in place on a follow-up waiting event (no repeat toast — guards against a permission storm).
- **Identity/ReminderIdentity** — pure derivation from a payload: `project` = basename(repoRoot), `worktreeGlyph` (branch last-segment initial, or `●` for main/none), `colorIndex` = stable FNV-1a hash of repoRoot mod palette size.
- **Identity/ReminderPalette** — 12-color categorical palette; worktree tabs render a lightened variant of the project color; glyph foreground flips black/white by luminance.
- **Panels/PanelFactory** — the shared `NSPanel` recipe: borderless + `.nonactivatingPanel`, floating, clear background, `canJoinAllSpaces`/`fullScreenAuxiliary`, `canBecomeKey` only when interaction is needed. ToastPanel / TabStripPanel / DetailPanel build on it. DetailPanel measures content to size itself.
- **Actions/ItermFocusAction** — jumps to the pane. Maximize-on-click (menu toggle, `UserDefaults`) chooses between the machine-local `~/.claude/scripts/iterm-focus-pane.py` (focus + maximize) and the `it2` CLI (`app activate` + `session focus`, focus only). `plan()` is pure/tested.
- **Hook/HookStatus + Hook/HookInstaller** — the menu status light. HookStatus reads `~/.claude/settings.json`; HookInstaller copies the bundled scripts to App Support and appends three hooks — Stop (`mate-notify.js`), SessionStart (`mate-session-start.js`), and Notification (`mate-notify.js --event notification`, matcher `permission_prompt`) — each idempotent, append-only, preserving other hooks. Markers are per-event, so Stop and Notification sharing `mate-notify.js` never cross-delete. The canonical scripts live under `Sources/ClaudeItermMate/Resources/` and load at runtime via `Bundle.module`. **Upgrade path**: `AppDelegate` re-runs the idempotent `install()` on launch when the hook is already installed, so a new bundled hook/script (e.g. the Notification hook) propagates to existing users without a manual remove+reinstall (the menu only offers Install when *not* installed).
- **MenuBar/MenuBarController** — `NSMenuDelegate`; rebuilds on `menuNeedsUpdate` so the hook light reflects live settings.json. `menu.autoenablesItems = false` is required — otherwise AppKit re-enables items by target and the "disabled until installed" state silently breaks.

## Constraints

- macOS 14+, Swift tools 5.9, **no external Swift dependencies**, POSIX sockets only.
- Never modify `~/.claude/scripts/desktop-notify.js`. The hook installer *does* write `~/.claude/settings.json` (that is its purpose) but tests must never touch the real file — inject temp paths / test JSON into the pure functions.

## Gotchas

- **Paths with spaces**: the install path is `~/Library/Application Support/...` (a space). Any command written for a shell/`node`, and any path parsed out of a command, must handle the space — quote when writing (`node "<path>"`), and extract the whole path (not a whitespace-split token) when reading. Two separate bugs in this repo came from this; both have regression tests.
- **SourceKit false positives**: the editor often reports `Cannot find type '...'` / `No such module 'XCTest'` for cross-file symbols because it indexes files outside the SwiftPM build graph. These are noise — trust `swift build` / `swift test`, not the inline diagnostics.
