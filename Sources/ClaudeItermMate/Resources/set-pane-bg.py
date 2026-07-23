#!/usr/bin/env python3
"""Set a specific iTerm2 session's background color via the iTerm2 Python API.

Canonical reference copy. Install it (machine-local, like iterm-focus-pane.py):
  cp set-pane-bg.py ~/.claude/scripts/set-pane-bg.py
  chmod +x ~/.claude/scripts/set-pane-bg.py
and set its shebang to a Python that has the `iterm2` package (typically the
`it2` CLI's venv, e.g. ~/.local/share/uv/tools/it2/bin/python). ItermBgColorAction
spawns ~/.claude/scripts/set-pane-bg.py directly.

Invoked by ClaudeItermMate on SessionStart with the session UUID (the part
after ':' in ITERM_SESSION_ID) and an RRGGBB hex. Applies a per-session profile
override so only that pane's background changes; it does NOT touch the tty, so a
running Claude TUI is unaffected. All failures exit silently — the caller
ignores this script's outcome.

Exit guarantees (mirrors iterm-focus-pane.py):
  - os._exit(0) after the work is done (iterm2.run_until_complete does not
    return after main() completes).
  - signal.alarm(10) as a hard backstop if the API connection hangs.

Usage: set-pane-bg.py <session-uuid> <RRGGBB>
"""

import os
import signal
import subprocess
import sys

import iterm2


def ensure_cookie():
    """The API needs ITERM2_COOKIE when not launched from within iTerm2."""
    if os.environ.get("ITERM2_COOKIE"):
        return True
    try:
        cookie = subprocess.run(
            ["osascript", "-e", 'tell application "iTerm2" to request cookie'],
            capture_output=True,
            text=True,
            timeout=3,
        ).stdout.strip()
    except Exception:
        return False
    if not cookie:
        return False
    os.environ["ITERM2_COOKIE"] = cookie
    return True


async def main(connection):
    session_id = sys.argv[1]
    hexstr = sys.argv[2].lstrip("#")
    r, g, b = (int(hexstr[i:i + 2], 16) for i in (0, 2, 4))
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is not None:
        change = iterm2.LocalWriteOnlyProfile()
        change.set_background_color(iterm2.Color(r, g, b))
        await session.async_set_profile_properties(change)
    os._exit(0)  # run_until_complete never returns; force clean exit


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(1)
    signal.alarm(10)  # hard backstop: never leave a lingering process
    if not ensure_cookie():
        sys.exit(1)
    try:
        iterm2.run_until_complete(main)
    except Exception:
        pass
    sys.exit(1)
