import Foundation
import os

/// Sets a Claude Code session's iTerm2 pane background color by spawning the
/// bundled `set-pane-bg.py` (iTerm2 Python API — a per-session profile override
/// that never touches the tty, so a running Claude TUI is unaffected).
///
/// This is the profile-layer half of session coloring: it works entirely through
/// the session's profile, so it needs no composer interaction and cannot disturb
/// whatever is running in the pane. The prompt-bar half lives in the sibling
/// `ItermColorAction`, which does inject keystrokes. Fire-and-forget; any failure
/// is logged and otherwise ignored. Mirrors `ItermFocusAction`'s script-spawn
/// shape: the script is published to App Support by `ScriptInstaller` and run
/// through an explicit interpreter, never via its own shebang.
///
/// `reset` runs the same script with a sentinel instead of a hex, restoring the
/// pane to its profile default when Claude Code exits.
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

    /// Pure, unit-tested argv builder for the interpreter: script path first.
    static func arguments(scriptPath: String, sessionUUID: String, hex: String) -> [String] {
        [scriptPath] + arguments(sessionUUID: sessionUUID, hex: hex)
    }

    /// Pure, unit-tested argv builder for the reset (Claude Code exited).
    static func resetArguments(sessionUUID: String) -> [String] {
        [sessionUUID, resetSentinel]
    }

    /// Interpreter form of `resetArguments`, mirroring the `apply` pair.
    static func resetArguments(scriptPath: String, sessionUUID: String) -> [String] {
        [scriptPath] + resetArguments(sessionUUID: sessionUUID)
    }

    func apply(sessionUUID: String, hex: String) {
        spawn(
            Self.arguments(scriptPath: scriptURL.path, sessionUUID: sessionUUID, hex: hex),
            what: "pane color"
        )
    }

    /// Restore the pane's background to its profile default, undoing our
    /// per-session override. Same script, same gate, same fire-and-forget shape
    /// as `apply`.
    func reset(sessionUUID: String) {
        spawn(
            Self.resetArguments(scriptPath: scriptURL.path, sessionUUID: sessionUUID),
            what: "pane color reset"
        )
    }

    /// `argv` already carries the script path in front: what we execute is the
    /// interpreter, never the script itself — its shebang is decorative and
    /// would resolve to a Python without `iterm2`.
    private func spawn(_ argv: [String], what: String) {
        guard available, let interpreter else {
            Self.log.info("set-pane-bg.py or its interpreter unavailable; \(what) skipped")
            return
        }
        let p = Process()
        p.executableURL = interpreter
        p.arguments = argv
        do {
            try p.run()
        } catch {
            Self.log.error("\(what) spawn failed: \(error.localizedDescription)")
        }
    }
}
