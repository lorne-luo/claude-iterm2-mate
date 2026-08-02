import Foundation
import os

/// Sets a Claude Code session's iTerm2 pane background color by spawning the
/// bundled `set-pane-bg.py` (iTerm2 Python API — a per-session profile override
/// that never touches the tty, so a running Claude TUI is unaffected).
///
/// Replaces the old `/color` keystroke injection: no ctrl+s stash, no `\r`
/// submit, no composer interference. Fire-and-forget; any failure is logged and
/// otherwise ignored. Mirrors `ItermFocusAction`'s script-spawn shape: the
/// script is published to App Support by `ScriptInstaller` and run through an
/// explicit interpreter, never via its own shebang.
struct ItermBgColorAction {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermBgColor")

    static var defaultScriptURL: URL { ScriptInstaller.destURL(for: "set-pane-bg") }

    let scriptURL: URL
    let interpreter: URL?

    init(
        scriptURL: URL = ItermBgColorAction.defaultScriptURL,
        interpreter: URL? = PythonInterpreter.resolve()
    ) {
        self.scriptURL = scriptURL
        self.interpreter = interpreter
    }

    /// Both halves are required: the script alone cannot run without a Python
    /// that has `iterm2`, which comes from the `it2` venv.
    var available: Bool {
        interpreter != nil && FileManager.default.fileExists(atPath: scriptURL.path)
    }

    /// Pure, unit-tested argv builder: session UUID + RRGGBB hex.
    static func arguments(sessionUUID: String, hex: String) -> [String] {
        [sessionUUID, hex]
    }

    /// Pure, unit-tested argv builder for the interpreter: script path first.
    static func arguments(scriptPath: String, sessionUUID: String, hex: String) -> [String] {
        [scriptPath] + arguments(sessionUUID: sessionUUID, hex: hex)
    }

    func apply(sessionUUID: String, hex: String) {
        guard available, let interpreter else {
            Self.log.info("set-pane-bg.py or its interpreter unavailable; pane color skipped")
            return
        }
        let p = Process()
        p.executableURL = interpreter
        p.arguments = Self.arguments(
            scriptPath: scriptURL.path, sessionUUID: sessionUUID, hex: hex
        )
        do {
            try p.run()
        } catch {
            Self.log.error("pane color spawn failed: \(error.localizedDescription)")
        }
    }
}
