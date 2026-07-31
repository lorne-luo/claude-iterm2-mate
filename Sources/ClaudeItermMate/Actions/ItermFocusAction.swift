import Foundation
import os

/// Jumps to the iTerm2 pane owning a session. Two mechanisms, fire-and-forget:
/// - maximize on: the bundled iterm-focus-pane.py (focus + "Maximize Active
///   Pane" via the iTerm2 Python API; self-exits within 10 s). Published to App
///   Support by `ScriptInstaller` and run through `PythonInterpreter`, never via
///   its own shebang.
/// - maximize off: the `it2` CLI (`app activate` + `session focus <uuid>`),
///   which selects the pane without maximizing it.
struct ItermFocusAction {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermFocus")

    /// UserDefaults key for the "maximize pane on click" toggle (default true).
    static let maximizeDefaultsKey = "maximizeOnClick"

    static var maximizeOnClick: Bool {
        get { UserDefaults.standard.object(forKey: maximizeDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: maximizeDefaultsKey) }
    }

    /// Which mechanism a click resolves to, given the toggle and availability.
    enum Plan: Equatable { case script, it2FocusOnly, unavailable }

    static var defaultScriptURL: URL { ScriptInstaller.destURL(for: "iterm-focus-pane") }

    /// Candidate locations for the `it2` CLI (focus-without-maximize path).
    private static var it2Candidates: [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/it2"),
            URL(fileURLWithPath: "/opt/homebrew/bin/it2"),
            URL(fileURLWithPath: "/usr/local/bin/it2"),
        ]
    }

    static func resolveIt2() -> URL? {
        it2Candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    let scriptURL: URL
    let it2URL: URL?
    let interpreter: URL?

    /// Derives the interpreter from the same `it2` — so a stubbed `it2URL` never
    /// reaches for the real machine's interpreter.
    init(
        scriptURL: URL = ItermFocusAction.defaultScriptURL,
        it2URL: URL? = ItermFocusAction.resolveIt2()
    ) {
        self.init(
            scriptURL: scriptURL, it2URL: it2URL,
            interpreter: PythonInterpreter.resolve(it2URL: it2URL)
        )
    }

    /// Fully explicit; `interpreter: nil` genuinely means "no interpreter"
    /// (a defaulted parameter could not express that without being overridden).
    init(scriptURL: URL, it2URL: URL?, interpreter: URL?) {
        self.scriptURL = scriptURL
        self.it2URL = it2URL
        self.interpreter = interpreter
    }

    /// The script needs a Python that has `iterm2`, which lives in the `it2`
    /// venv — so no `it2` means no maximizing script either.
    var scriptAvailable: Bool {
        interpreter != nil && FileManager.default.fileExists(atPath: scriptURL.path)
    }
    var it2Available: Bool { it2URL != nil }
    /// Can we jump at all? Drives the menu-bar warning state.
    var canFocus: Bool { scriptAvailable || it2Available }

    /// Pure decision — unit tested. Prefer the maximizing script when maximize
    /// is on; otherwise the it2 CLI; if only the script exists, use it even
    /// with maximize off (jumping+maximizing beats not jumping).
    static func plan(maximize: Bool, scriptAvailable: Bool, it2Available: Bool) -> Plan {
        if maximize && scriptAvailable { return .script }
        if it2Available { return .it2FocusOnly }
        if scriptAvailable { return .script }
        return .unavailable
    }

    static func launch(interpreter: URL, scriptPath: String, sessionUUID: String) -> Process {
        let p = Process()
        p.executableURL = interpreter
        p.arguments = [scriptPath, sessionUUID]
        return p
    }

    static func it2Process(it2URL: URL, arguments: [String]) -> Process {
        let p = Process()
        p.executableURL = it2URL
        p.arguments = arguments
        return p
    }

    func focus(sessionUUID: String, maximize: Bool) {
        switch Self.plan(maximize: maximize, scriptAvailable: scriptAvailable, it2Available: it2Available) {
        case .script:
            guard let interpreter else { return } // unreachable: .script implies scriptAvailable
            run(Self.launch(
                interpreter: interpreter, scriptPath: scriptURL.path, sessionUUID: sessionUUID
            ))
        case .it2FocusOnly:
            guard let it2URL else { return }
            run(Self.it2Process(it2URL: it2URL, arguments: ["app", "activate"]))
            run(Self.it2Process(it2URL: it2URL, arguments: ["session", "focus", sessionUUID]))
        case .unavailable:
            Self.log.info("no focus mechanism available; tab removed without jumping")
        }
    }

    private func run(_ p: Process) {
        do {
            try p.run()
        } catch {
            Self.log.error("focus spawn failed: \(error.localizedDescription)")
        }
    }
}
