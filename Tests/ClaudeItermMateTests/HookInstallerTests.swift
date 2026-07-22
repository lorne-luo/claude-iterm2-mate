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

    // MARK: Notification hook

    private let notifCommand =
        "node \"/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js\" --event notification"

    /// The flat list of (command, matcher) pairs for a given event.
    private func groups(_ settings: [String: Any], event: String) -> [(command: String, matcher: String)] {
        guard
            let hooks = settings["hooks"] as? [String: Any],
            let evt = hooks[event] as? [[String: Any]]
        else { return [] }
        return evt.flatMap { group -> [(String, String)] in
            let matcher = group["matcher"] as? String ?? ""
            return (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                ($0["command"] as? String).map { ($0, matcher) }
            }
        }
    }

    func testAddsNotificationHookWithPermissionMatcher() {
        let result = HookInstaller.settingsByAddingHook(
            [:], command: notifCommand, event: "Notification",
            marker: "--event notification", matcher: "permission_prompt"
        )
        let g = groups(result, event: "Notification")
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].command, notifCommand)
        XCTAssertEqual(g[0].matcher, "permission_prompt")
    }

    func testNotificationHookIdempotent() {
        let once = HookInstaller.settingsByAddingHook(
            [:], command: notifCommand, event: "Notification",
            marker: "--event notification", matcher: "permission_prompt"
        )
        let twice = HookInstaller.settingsByAddingHook(
            once, command: notifCommand, event: "Notification",
            marker: "--event notification", matcher: "permission_prompt"
        )
        XCTAssertEqual(groups(twice, event: "Notification").count, 1)
    }

    func testStopAndNotificationCoexistWithoutCrossDeletion() {
        // Both hooks use mate-notify.js; installing the Notification hook must not
        // touch the Stop hook, and removing one must leave the other.
        var s = HookInstaller.settingsByAddingHook([:], command: command)
        s = HookInstaller.settingsByAddingHook(
            s, command: notifCommand, event: "Notification",
            marker: "--event notification", matcher: "permission_prompt"
        )
        XCTAssertEqual(stopCommands(s), [command])
        XCTAssertEqual(groups(s, event: "Notification").map(\.command), [notifCommand])

        let removedNotif = HookInstaller.settingsByRemovingHook(
            s, event: "Notification", marker: "--event notification"
        )
        XCTAssertEqual(stopCommands(removedNotif), [command], "removing Notification must keep Stop")
        XCTAssertTrue(groups(removedNotif, event: "Notification").isEmpty)
    }

    func testRemovingStopLeavesNotification() {
        var s = HookInstaller.settingsByAddingHook([:], command: command)
        s = HookInstaller.settingsByAddingHook(
            s, command: notifCommand, event: "Notification",
            marker: "--event notification", matcher: "permission_prompt"
        )
        let removedStop = HookInstaller.settingsByRemovingHook(s) // Stop, mate-notify.js
        XCTAssertTrue(stopCommands(removedStop).isEmpty)
        XCTAssertEqual(groups(removedStop, event: "Notification").map(\.command), [notifCommand],
                       "removing Stop must not remove the Notification hook")
    }

    func testNotificationHookCommandFormat() {
        let path = "/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js"
        XCTAssertEqual(
            HookInstaller.notificationHookCommand(scriptPath: path),
            "node \"\(path)\" --event notification"
        )
    }
}
