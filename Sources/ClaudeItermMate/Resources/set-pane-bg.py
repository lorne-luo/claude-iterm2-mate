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

With "default" in place of the hex (sent when Claude Code exits) it restores the
pane to its underlying profile background instead. iTerm2 2.20 has no call to
drop a per-session override, and async_get_profile() returns the MERGED value —
so the real base value is read via Profile.original_guid (the shared profile this
session was derived from; None when it was never overridden) and re-applied
through the same LocalWriteOnlyProfile mechanism. The override therefore still
exists, it just holds the default value again; visually identical (verified live).

Exit guarantees (mirrors iterm-focus-pane.py):
  - os._exit(0) after the work is done (iterm2.run_until_complete does not
    return after main() completes).
  - signal.alarm(10) as a hard backstop if the API connection hangs.

Usage: set-pane-bg.py <session-uuid> <RRGGBB|default>
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


async def base_background_color(connection, session):
    """The background color saved in the profile this session derives from.

    original_guid points at the shared profile whenever the session carries any
    per-session override, and is None when it carries none — in which case .guid
    already is the shared profile's guid. Profile.async_get() reads the saved
    profiles, bypassing session overrides (async_get_profile() would just hand
    back the color we are trying to undo). None when the guid resolves to
    nothing (e.g. the profile was deleted).
    """
    current = await session.async_get_profile()
    base_guid = current.original_guid or current.guid
    profiles = await iterm2.Profile.async_get(connection, [base_guid])
    return profiles[0].background_color if profiles else None


async def main(connection):
    session_id = sys.argv[1]
    arg = sys.argv[2]
    resetting = arg.lower() == "default"
    if not resetting:
        hexstr = arg.lstrip("#")
        r, g, b = (int(hexstr[i:i + 2], 16) for i in (0, 2, 4))
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is not None:
        if resetting:
            color = await base_background_color(connection, session)
        else:
            color = iterm2.Color(r, g, b)
        if color is not None:
            change = iterm2.LocalWriteOnlyProfile()
            change.set_background_color(color)
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
