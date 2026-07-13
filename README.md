# Claude iTerm2 Mate

A macOS menu-bar companion for Claude Code running in iTerm2. When Claude
finishes a reply you get a toast; after it fades, a reminder tab is queued on
the right edge of the screen — one per iTerm2 session. Each tab is colored by
its git project (all worktrees of a repo share the base color; a linked
worktree uses a lighter tint) and shows a glyph for the branch (the first
letter of the branch's last path segment, or ● for main/master). Hover a tab to
read the full reply; click it to jump to the owning iTerm2 pane (focused +
maximized).

## Requirements

- macOS 14+
- iTerm2 with the Python API enabled
- [it2](https://pypi.org/project/it2/) (`uv tool install it2`) and
  `~/.claude/scripts/iterm-focus-pane.py` for click-to-focus
- Node.js (for the Claude Code hook)

## Build & run

    swift run -c release

## Hook installation

Open the menu-bar menu and click **Install me** (shown with a red dot when the
hook is not yet registered). This copies the bundled `mate-notify.js` to
`~/Library/Application Support/ClaudeItermMate/mate-notify.js` and appends a
`Stop` hook pointing at it in `~/.claude/settings.json`. The install is
append-only and idempotent — it never touches your other hooks (`afplay`,
`desktop-notify.js`, etc.). Once installed the menu shows a green **Hook
active** label.

If the app is not running, the hook falls back to a normal macOS
notification — behavior degrades gracefully to the status quo.

## Menu bar

Pause reminders · Clear all tabs · Launch at login · Quit.
A warning icon means either it2/iterm-focus-pane.py was not found (tabs still
work but clicking won't jump — `uv tool install it2` to fix) or the socket
server failed to start (the menu shows the reason).

**Launch at login** only works from a bundled `.app`; it is a no-op when the
app is started via `swift run` (`SMAppService` requires a registered bundle).
To use it, wrap the built binary in an `.app` bundle and launch that.
