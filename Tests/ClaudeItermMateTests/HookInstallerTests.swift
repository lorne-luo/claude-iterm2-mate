import XCTest
@testable import ClaudeItermMate

final class HookInstallerTests: XCTestCase {
    private let command = "node /Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js"

    /// Pull the flat list of Stop command strings out of a settings dict.
    private func stopCommands(_ settings: [String: Any]) -> [String] {
        guard
            let hooks = settings["hooks"] as? [String: Any],
            let stop = hooks["Stop"] as? [[String: Any]]
        else { return [] }
        return stop.flatMap { group -> [String] in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    func testCreatesHooksStopFromEmpty() {
        let result = HookInstaller.settingsByAddingHook([:], command: command)
        XCTAssertEqual(stopCommands(result), [command])
    }

    func testAppendsAndPreservesUnrelatedHook() {
        let afplay = "afplay /System/Library/Sounds/Glass.aiff"
        let existing: [String: Any] = [
            "hooks": ["Stop": [["matcher": "", "hooks": [["type": "command", "command": afplay]]]]],
            "otherKey": "kept",
        ]
        let result = HookInstaller.settingsByAddingHook(existing, command: command)
        XCTAssertEqual(stopCommands(result), [afplay, command])
        XCTAssertEqual(result["otherKey"] as? String, "kept")
    }

    func testIdempotentWhenAlreadyPresent() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["matcher": "", "hooks": [
                ["type": "command", "command": "node /elsewhere/mate-notify.js"],
            ]]]],
        ]
        let result = HookInstaller.settingsByAddingHook(existing, command: command)
        XCTAssertEqual(stopCommands(result), ["node /elsewhere/mate-notify.js"])
    }

    func testHookCommandQuotesPathWithSpaces() {
        let path = "/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js"
        XCTAssertEqual(HookInstaller.hookCommand(scriptPath: path), "node \"\(path)\"")
    }

    func testIdempotentWhenAlreadyPresentAsQuotedCommand() {
        let quoted = "node \"/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js\""
        let existing: [String: Any] = [
            "hooks": ["Stop": [["matcher": "", "hooks": [
                ["type": "command", "command": quoted],
            ]]]],
        ]
        let result = HookInstaller.settingsByAddingHook(existing, command: command)
        XCTAssertEqual(stopCommands(result), [quoted])
    }

    // MARK: removal

    func testRemovesHookAndPreservesUnrelatedInSameGroup() {
        let afplay = "afplay /System/Library/Sounds/Glass.aiff"
        let existing: [String: Any] = [
            "hooks": ["Stop": [["matcher": "", "hooks": [
                ["type": "command", "command": afplay],
                ["type": "command", "command": command],
            ]]]],
            "otherKey": "kept",
        ]
        let result = HookInstaller.settingsByRemovingHook(existing)
        XCTAssertEqual(stopCommands(result), [afplay])
        XCTAssertEqual(result["otherKey"] as? String, "kept")
    }

    func testRemovalDropsEmptiedGroupButKeepsOthers() {
        let afplay = "afplay /x.aiff"
        let existing: [String: Any] = [
            "hooks": ["Stop": [
                ["matcher": "", "hooks": [["type": "command", "command": command]]],
                ["matcher": "", "hooks": [["type": "command", "command": afplay]]],
            ]],
        ]
        let result = HookInstaller.settingsByRemovingHook(existing)
        XCTAssertEqual(stopCommands(result), [afplay])
        let stop = (result["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1, "the emptied group should be dropped")
    }

    func testRemovalNoOpWhenAbsent() {
        let afplay = "afplay /x.aiff"
        let existing: [String: Any] = [
            "hooks": ["Stop": [["matcher": "", "hooks": [["type": "command", "command": afplay]]]]],
        ]
        let result = HookInstaller.settingsByRemovingHook(existing)
        XCTAssertEqual(stopCommands(result), [afplay])
    }
}
