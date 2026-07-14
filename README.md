# Claude iTerm2 Mate

A macOS menu-bar companion for [Claude Code](https://claude.ai/code) sessions
running in iTerm2. When a Claude session finishes replying, you get a toast;
after it fades, a reminder tab is queued on the right edge of the screen — one
per iTerm2 session. Hover a tab to read the full reply; click it to jump
straight to the owning iTerm2 pane.

It runs as a background agent (`LSUIElement` / `.accessory`) — no Dock icon,
just a menu-bar item.

## Why

When you run several Claude Code sessions across iTerm2 panes, it's easy to
lose track of which one just finished and needs your attention. This app turns
each finished session into a persistent, color-coded tab you can glance at and
click to return to — so nothing sits idle waiting for you.

## Features

- **Toast on finish** — a 4-second toast flies in when a session's `Stop` hook
  fires, then hands off to a queued tab.
- **One tab per session** — the right-edge strip shows one tab per iTerm2
  session (deduped by session UUID); a new reply on the same session refreshes
  its existing tab instead of stacking a duplicate.
- **Project-colored tabs** — each tab is colored by its git project, so all
  sessions of one repo share a base color. A linked worktree renders a lighter
  tint of the project color, and a glyph shows the branch (the first letter of
  the branch's last path segment, or ● for main/master).
- **Hover for the full reply** — hovering a tab pops a detail panel with the
  complete message.
- **Click to jump** — clicking a tab focuses the originating iTerm2 pane (and
  maximizes it, if *Maximize Pane on Click* is enabled), then clears the tab.
- **Graceful fallback** — if the app isn't running, the hook falls back to a
  plain macOS desktop notification, so behavior degrades to the status quo.

## Requirements

- macOS 14+ on Apple Silicon (the released `.dmg` ships an arm64-only binary)
- iTerm2 with the Python API enabled
- Node.js (runs the Claude Code `Stop` hook)
- For click-to-focus: [it2](https://pypi.org/project/it2/)
  (`uv tool install it2`). *Maximize Pane on Click* additionally uses the
  machine-local `~/.claude/scripts/iterm-focus-pane.py` (focus + maximize).

## Build & run

```bash
swift build -c release   # release build
swift run -c release     # build and launch
```

*Launch at Login* only works from a bundled `.app` (`SMAppService` requires a
registered bundle); it is a no-op when started via `swift run`. To use it, wrap
the built binary in an `.app` bundle and launch that.

## Install

Download the latest `ClaudeItermMate-<version>.dmg` from
[Releases](https://github.com/lorne-luo/claude-iterm2-mate/releases), open it,
and drag **ClaudeItermMate** to Applications.

The app is unsigned, so Gatekeeper blocks the first launch. Either right-click
the app and choose **Open**, or clear the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeItermMate.app
```

## Releasing (maintainer)

```bash
./scripts/release.sh 1.2.0
```

This validates the working tree, pushes a `v1.2.0` tag, and GitHub Actions
builds the `.dmg` and publishes the GitHub Release. The version comes entirely
from the tag; nothing version-related is committed.

## Hook installation

Open the menu-bar menu → **Install Hook** (the status light is red when the
hook isn't registered yet). This:

1. Copies the bundled `mate-notify.js` to
   `~/Library/Application Support/ClaudeItermMate/mate-notify.js`.
2. Appends a `Stop` hook pointing at it in `~/.claude/settings.json`.

The install is **append-only and idempotent** — it never touches your other
hooks (`afplay`, `desktop-notify.js`, etc.). Once installed, the menu shows a
green **Hook installed** label. Use **Remove Hook…** to uninstall (with a
confirmation prompt).

## Menu bar

| Item | What it does |
| --- | --- |
| Hook status | Green when the `Stop` hook is registered; submenu to *Install Hook* / *Remove Hook…* |
| Clear All Tabs | Dismiss every queued reminder tab |
| Maximize Pane on Click | Toggle: focus + maximize the target pane, or focus only |
| Launch at Login | Toggle (requires a bundled `.app`) |
| Quit | Exit the app |

A warning row appears when either `it2` / `iterm-focus-pane.py` was not found
(tabs still work but clicking won't jump — `uv tool install it2` to fix) or the
socket server failed to start (the reason is shown inline).

## How it works

```
Claude Code Stop hook (Resources/mate-notify.js)
  --unix socket, one JSON message per connection (close = frame boundary)-->
NotifyServer  ->  NotifyPayload.decode  ->  ReminderStore.upsert
  ->  ReminderCoordinator (owns the toast timer; toasting -> queued)
  ->  ToastPanel (4s)  --fly-in-->  TabStripPanel (right edge)  --hover-->  DetailPanel
Click a tab  ->  ItermFocusAction (focus / focus+maximize)  ->  ReminderStore.remove
```

The app is an AppKit shell (`main.swift` + `AppDelegate`) hosting SwiftUI views
inside borderless, non-activating `NSPanel`s, with one-way data flow. The hook
talks to the app over a POSIX `AF_UNIX` socket at
`~/Library/Application Support/ClaudeItermMate/notify.sock` — one JSON message
per connection. A single-instance guard quits a second launch if the socket is
already connectable.

Source layout (`Sources/ClaudeItermMate/`):

| Area | Files |
| --- | --- |
| Socket server | `Server/NotifyServer`, `Server/NotifyPayload` |
| State | `Store/ReminderStore`, `ReminderCoordinator` |
| Tab identity & color | `Identity/ReminderIdentity`, `Identity/ReminderPalette` |
| Panels | `Panels/PanelFactory`, `Panels/ToastPanel`, `Panels/TabStripPanel`, `Panels/DetailPanel` |
| Focus action | `Actions/ItermFocusAction`, `Geometry/EdgeGeometry` |
| Hook management | `Hook/HookStatus`, `Hook/HookInstaller`, `Resources/mate-notify.js` |
| Menu bar | `MenuBar/MenuBarController` |

## Testing

```bash
swift test                                  # full suite
swift test --filter ReminderStoreTests      # one test class
```

Tests are pure-logic XCTest (no GUI). GUI behavior (toast / tab / hover / menu)
can't be verified headless — build, run, and drive it manually.

## Constraints

- macOS 14+, Swift tools 5.9, **no external Swift dependencies**, POSIX sockets
  only.
- The hook installer writes `~/.claude/settings.json` (that is its purpose) but
  never modifies `~/.claude/scripts/desktop-notify.js`.
