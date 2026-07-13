import XCTest
@testable import ClaudeItermMate

final class HookStatusTests: XCTestCase {
    /// Build a settings dict with the given Stop hook commands.
    private func settings(stopCommands: [String]) -> [String: Any] {
        let hooks = stopCommands.map { cmd -> [String: Any] in
            ["type": "command", "command": cmd]
        }
        return ["hooks": ["Stop": [["matcher": "", "hooks": hooks]]]]
    }

    func testInstalledWhenReferencedAndFileExists() {
        let s = settings(stopCommands: ["node /Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js"])
        let status = HookStatus.evaluate(settings: s, fileExists: { _ in true })
        XCTAssertEqual(status, .installed)
    }

    func testInstalledWhenPathContainsSpaces() {
        // The real install path has a space ("Application Support"); fileExists
        // must be checked against the FULL path, not a whitespace-split token.
        let full = "/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js"
        let s = settings(stopCommands: ["node \(full)"])
        let status = HookStatus.evaluate(settings: s, fileExists: { $0 == full })
        XCTAssertEqual(status, .installed)
    }

    func testNotInstalledWhenReferencedButFileMissing() {
        let s = settings(stopCommands: ["node /somewhere/mate-notify.js"])
        let status = HookStatus.evaluate(settings: s, fileExists: { _ in false })
        XCTAssertEqual(status, .notInstalled)
    }

    func testNotInstalledWhenNoReference() {
        let s = settings(stopCommands: ["afplay /System/Library/Sounds/Glass.aiff"])
        let status = HookStatus.evaluate(settings: s, fileExists: { _ in true })
        XCTAssertEqual(status, .notInstalled)
    }

    func testNotInstalledWhenSettingsNil() {
        XCTAssertEqual(HookStatus.evaluate(settings: nil, fileExists: { _ in true }), .notInstalled)
    }

    func testDetectedAcrossMultipleGroupsAndCommands() {
        let hooks: [String: Any] = ["hooks": ["Stop": [
            ["matcher": "", "hooks": [["type": "command", "command": "afplay /x.aiff"]]],
            ["matcher": "", "hooks": [
                ["type": "command", "command": "echo hi"],
                ["type": "command", "command": "node /opt/tools/mate-notify.js"],
            ]],
        ]]]
        let existing = "/opt/tools/mate-notify.js"
        let status = HookStatus.evaluate(settings: hooks, fileExists: { $0 == existing })
        XCTAssertEqual(status, .installed)
    }
}
