#!/usr/bin/env python3
# ^ decorative only. ScriptInstaller never sets +x and ItermFocusAction spawns
#   this file as `<interpreter> <this-path> <uuid>`, where the interpreter is
#   PythonInterpreter.resolve() -> the it2 CLI's venv python (the one that has
#   `iterm2`). /usr/bin/python3 does NOT have it.
"""Focus the iTerm2 pane owning a session and maximize it.

Bundled with the app and published to
~/Library/Application Support/ClaudeItermMate/ by ScriptInstaller on launch.
Invoked by ItermFocusAction with the session UUID (the part after ':' in
ITERM_SESSION_ID). Brings iTerm2 to the foreground, selects the
window/tab/pane, then toggles "Maximize Active Pane" unless the pane is
already maximized or is the only pane in its tab.

All failures exit silently — the caller ignores this script's outcome.

Exit guarantees (this runs many times a day, must never linger):
  - os._exit(0) after the work is done, because iterm2.run_until_complete()
    does not return after main() completes (verified: it hangs).
  - signal.alarm(10) as a hard backstop if the API connection hangs.

Usage: iterm-focus-pane.py <session-uuid>
"""

import os
import signal
import subprocess
import sys

import iterm2

MAXIMIZE_MENU_ID = "Maximize Active Pane"


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
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is not None:
        # Select the right window/tab/pane, then bring iTerm2 to the front.
        await session.async_activate(select_tab=True, order_window_front=True)
        await app.async_activate(raise_all_windows=False, ignoring_other_apps=True)
        # Maximize only when possible: the menu item is disabled for
        # single-pane tabs and checked when already maximized.
        state = await iterm2.MainMenu.async_get_menu_item_state(
            connection, MAXIMIZE_MENU_ID
        )
        if state.enabled and not state.checked:
            await iterm2.MainMenu.async_select_menu_item(connection, MAXIMIZE_MENU_ID)
    os._exit(0)  # run_until_complete never returns; force clean exit


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    signal.alarm(10)  # hard backstop: never leave a lingering process
    if not ensure_cookie():
        sys.exit(1)
    try:
        iterm2.run_until_complete(main)
    except Exception:
        pass
    sys.exit(1)
