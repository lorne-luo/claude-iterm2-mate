import Foundation
import os

/// Sets a Claude Code session's iTerm2 pane background color by spawning the
/// machine-local `set-pane-bg.py` (iTerm2 Python API — a per-session profile
/// override that never touches the tty, so a running Claude TUI is unaffected).
///
/// Replaces the old `/color` keystroke injection: no ctrl+s stash, no `\r`
/// submit, no composer interference. Fire-and-forget; any failure is logged and
/// otherwise ignored. Mirrors `ItermFocusAction`'s script-spawn shape.
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

    /// Pure, unit-tested argv builder: session UUID + RRGGBB hex.
    static func arguments(sessionUUID: String, hex: String) -> [String] {
        [sessionUUID, hex]
    }

    func apply(sessionUUID: String, hex: String) {
        guard available else {
            Self.log.info("set-pane-bg.py unavailable; pane color skipped")
            return
        }
        let p = Process()
        p.executableURL = scriptURL
        p.arguments = Self.arguments(sessionUUID: sessionUUID, hex: hex)
        do {
            try p.run()
        } catch {
            Self.log.error("pane color spawn failed: \(error.localizedDescription)")
        }
    }
}
