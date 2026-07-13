import Foundation
import os

/// Jumps to the iTerm2 pane owning a session. Two mechanisms, fire-and-forget:
/// - maximize on: the machine-local iterm-focus-pane.py (focus + "Maximize
///   Active Pane" via the it2 Python API; self-exits within 10 s).
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

    static var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/scripts/iterm-focus-pane.py")
    }

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

    init(scriptURL: URL = ItermFocusAction.defaultScriptURL, it2URL: URL? = ItermFocusAction.resolveIt2()) {
        self.scriptURL = scriptURL
        self.it2URL = it2URL
    }

    var scriptAvailable: Bool { FileManager.default.isExecutableFile(atPath: scriptURL.path) }
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

    static func launch(processFor url: URL, sessionUUID: String) -> Process {
        let p = Process()
        p.executableURL = url
        p.arguments = [sessionUUID]
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
            run(Self.launch(processFor: scriptURL, sessionUUID: sessionUUID))
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
