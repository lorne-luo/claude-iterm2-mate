import Foundation
import os

/// Spawns the machine-local iterm-focus-pane.py (it2 python environment)
/// to focus + maximize the iTerm2 pane owning a session. Fire-and-forget:
/// the script guarantees its own exit within 10 s; failures are silent.
struct ItermFocusAction {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermFocus")

    static var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/scripts/iterm-focus-pane.py")
    }

    let scriptURL: URL

    init(scriptURL: URL = ItermFocusAction.defaultScriptURL) {
        self.scriptURL = scriptURL
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: scriptURL.path)
    }

    static func launch(processFor url: URL, sessionUUID: String) -> Process {
        let p = Process()
        p.executableURL = url
        p.arguments = [sessionUUID]
        return p
    }

    func focus(sessionUUID: String) {
        guard isAvailable else {
            Self.log.info("focus script unavailable; tab removed without jumping")
            return
        }
        let p = Self.launch(processFor: scriptURL, sessionUUID: sessionUUID)
        do {
            try p.run()
        } catch {
            Self.log.error("focus spawn failed: \(error.localizedDescription)")
        }
    }
}
