import Foundation
import os

/// Sets a Claude Code session's iTerm2 pane background color by spawning the
/// machine-local `set-pane-bg.py` (iTerm2 Python API — a per-session profile
/// override that never touches the tty, so a running Claude TUI is unaffected).
///
/// This is the profile-layer half of session coloring: it works entirely through
/// the session's profile, so it needs no composer interaction and cannot disturb
/// whatever is running in the pane. The prompt-bar half lives in the sibling
/// `ItermColorAction`, which does inject keystrokes. Fire-and-forget; any failure
/// is logged and otherwise ignored. Mirrors `ItermFocusAction`'s script-spawn shape.
///
/// `reset` runs the same script with a sentinel instead of a hex, restoring the
/// pane to its profile default when Claude Code exits.
struct ItermBgColorAction {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermBgColor")

    static var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/scripts/set-pane-bg.py")
    }

    let scriptURL: URL

    init(scriptURL: URL = ItermBgColorAction.defaultScriptURL) {
        self.scriptURL = scriptURL
    }

    var available: Bool { FileManager.default.isExecutableFile(atPath: scriptURL.path) }

    /// Second argument that asks the script to restore the pane's underlying
    /// profile background instead of applying a hex. NOT related to `/color
    /// default`, the hue `ReminderPalette` deliberately excludes because it
    /// *clears* Claude Code's prompt-bar color; here it names the iTerm2 profile's
    /// own saved background.
    ///
    /// Degraded path: an older installed `set-pane-bg.py` cannot parse it as hex —
    /// `int(...)` raises an uncaught ValueError inside `run_until_complete` and a
    /// traceback goes to the app's inherited stderr. The pane outcome is still
    /// correct (background unchanged, so it keeps its project color), which is the
    /// part that matters; nothing user-facing breaks.
    static let resetSentinel = "default"

    /// Pure, unit-tested argv builder: session UUID + RRGGBB hex.
    static func arguments(sessionUUID: String, hex: String) -> [String] {
        [sessionUUID, hex]
    }

    /// Pure, unit-tested argv builder for the reset (Claude Code exited).
    static func resetArguments(sessionUUID: String) -> [String] {
        [sessionUUID, resetSentinel]
    }

    func apply(sessionUUID: String, hex: String) {
        spawn(Self.arguments(sessionUUID: sessionUUID, hex: hex), what: "pane color")
    }

    /// Restore the pane's background to its profile default, undoing our
    /// per-session override. Same script, same gate, same fire-and-forget shape
    /// as `apply`.
    func reset(sessionUUID: String) {
        spawn(Self.resetArguments(sessionUUID: sessionUUID), what: "pane color reset")
    }

    private func spawn(_ arguments: [String], what: String) {
        guard available else {
            Self.log.info("set-pane-bg.py unavailable; \(what) skipped")
            return
        }
        let p = Process()
        p.executableURL = scriptURL
        p.arguments = arguments
        do {
            try p.run()
        } catch {
            Self.log.error("\(what) spawn failed: \(error.localizedDescription)")
        }
    }
}
