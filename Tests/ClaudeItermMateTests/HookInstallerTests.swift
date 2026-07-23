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

    // Marker is the script name (app-specific), matching install()/uninstall().
    private let notifMarker = "mate-notify.js"

    func testAddsNotificationHookWithPermissionMatcher() {
        let result = HookInstaller.settingsByAddingHook(
            [:], command: notifCommand, event: "Notification",
            marker: notifMarker, matcher: "permission_prompt"
        )
        let g = groups(result, event: "Notification")
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].command, notifCommand)
        XCTAssertEqual(g[0].matcher, "permission_prompt")
    }

    func testNotificationHookIdempotent() {
        let once = HookInstaller.settingsByAddingHook(
            [:], command: notifCommand, event: "Notification",
            marker: notifMarker, matcher: "permission_prompt"
        )
        let twice = HookInstaller.settingsByAddingHook(
            once, command: notifCommand, event: "Notification",
            marker: notifMarker, matcher: "permission_prompt"
        )
        XCTAssertEqual(groups(twice, event: "Notification").count, 1)
    }

    func testStopAndNotificationCoexistWithoutCrossDeletion() {
        // Both hooks use mate-notify.js; installing the Notification hook must not
        // touch the Stop hook, and removing one must leave the other.
        var s = HookInstaller.settingsByAddingHook([:], command: command)
        s = HookInstaller.settingsByAddingHook(
            s, command: notifCommand, event: "Notification",
            marker: notifMarker, matcher: "permission_prompt"
        )
        XCTAssertEqual(stopCommands(s), [command])
        XCTAssertEqual(groups(s, event: "Notification").map(\.command), [notifCommand])

        let removedNotif = HookInstaller.settingsByRemovingHook(
            s, event: "Notification", marker: notifMarker
        )
        XCTAssertEqual(stopCommands(removedNotif), [command], "removing Notification must keep Stop")
        XCTAssertTrue(groups(removedNotif, event: "Notification").isEmpty)
    }

    func testRemovingStopLeavesNotification() {
        var s = HookInstaller.settingsByAddingHook([:], command: command)
        s = HookInstaller.settingsByAddingHook(
            s, command: notifCommand, event: "Notification",
            marker: notifMarker, matcher: "permission_prompt"
        )
        let removedStop = HookInstaller.settingsByRemovingHook(s) // Stop, mate-notify.js
        XCTAssertTrue(stopCommands(removedStop).isEmpty)
        XCTAssertEqual(groups(removedStop, event: "Notification").map(\.command), [notifCommand],
                       "removing Stop must not remove the Notification hook")
    }

    // The app-specific marker must not match an unrelated Notification hook that
    // merely passes `--event notification`: our install must still add ours, and
    // uninstall must leave the stranger untouched.
    func testNotificationMarkerIgnoresUnrelatedEventFlagHook() {
        let stranger = "node /opt/other-tool.js --event notification"
        var s = HookInstaller.settingsByAddingHook(
            [:], command: stranger, event: "Notification", marker: "other-tool", matcher: "permission_prompt"
        )
        // Our add is not blocked by the stranger's `--event notification`.
        s = HookInstaller.settingsByAddingHook(
            s, command: notifCommand, event: "Notification", marker: notifMarker, matcher: "permission_prompt"
        )
        XCTAssertEqual(groups(s, event: "Notification").map(\.command), [stranger, notifCommand])
        // Uninstalling ours leaves the stranger in place.
        let removed = HookInstaller.settingsByRemovingHook(s, event: "Notification", marker: notifMarker)
        XCTAssertEqual(groups(removed, event: "Notification").map(\.command), [stranger])
    }

    func testNotificationHookCommandFormat() {
        let path = "/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js"
        XCTAssertEqual(
            HookInstaller.notificationHookCommand(scriptPath: path),
            "node \"\(path)\" --event notification"
        )
    }

    // MARK: - AskUserQuestion (PreToolUse + PostToolUse)

    private let askCommand =
        "node \"/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js\" --event ask"
    private let askDoneCommand =
        "node \"/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js\" --event ask-done"

    func testAddsAskHooksWithAskUserQuestionMatcher() {
        var s = HookInstaller.settingsByAddingHook(
            [:], command: askCommand, event: "PreToolUse", marker: notifMarker, matcher: "AskUserQuestion"
        )
        s = HookInstaller.settingsByAddingHook(
            s, command: askDoneCommand, event: "PostToolUse", marker: notifMarker, matcher: "AskUserQuestion"
        )
        let pre = groups(s, event: "PreToolUse")
        let post = groups(s, event: "PostToolUse")
        XCTAssertEqual(pre.map(\.command), [askCommand])
        XCTAssertEqual(pre.first?.matcher, "AskUserQuestion")
        XCTAssertEqual(post.map(\.command), [askDoneCommand])
        XCTAssertEqual(post.first?.matcher, "AskUserQuestion")
    }

    func testAskHooksIdempotent() {
        var s = HookInstaller.settingsByAddingHook(
            [:], command: askCommand, event: "PreToolUse", marker: notifMarker, matcher: "AskUserQuestion"
        )
        s = HookInstaller.settingsByAddingHook(
            s, command: askCommand, event: "PreToolUse", marker: notifMarker, matcher: "AskUserQuestion"
        )
        XCTAssertEqual(groups(s, event: "PreToolUse").count, 1)
    }

    // All four events share the mate-notify.js marker; per-event scoping must
    // keep them independent on both install and removal.
    func testFourEventsCoexistWithoutCrossDeletion() {
        var s = HookInstaller.settingsByAddingHook([:], command: command) // Stop
        s = HookInstaller.settingsByAddingHook(
            s, command: notifCommand, event: "Notification", marker: notifMarker, matcher: "permission_prompt"
        )
        s = HookInstaller.settingsByAddingHook(
            s, command: askCommand, event: "PreToolUse", marker: notifMarker, matcher: "AskUserQuestion"
        )
        s = HookInstaller.settingsByAddingHook(
            s, command: askDoneCommand, event: "PostToolUse", marker: notifMarker, matcher: "AskUserQuestion"
        )
        XCTAssertEqual(stopCommands(s), [command])
        XCTAssertEqual(groups(s, event: "Notification").map(\.command), [notifCommand])
        XCTAssertEqual(groups(s, event: "PreToolUse").map(\.command), [askCommand])
        XCTAssertEqual(groups(s, event: "PostToolUse").map(\.command), [askDoneCommand])

        // Removing PreToolUse leaves the other three untouched.
        let r = HookInstaller.settingsByRemovingHook(s, event: "PreToolUse", marker: notifMarker)
        XCTAssertTrue(groups(r, event: "PreToolUse").isEmpty)
        XCTAssertEqual(stopCommands(r), [command])
        XCTAssertEqual(groups(r, event: "Notification").map(\.command), [notifCommand])
        XCTAssertEqual(groups(r, event: "PostToolUse").map(\.command), [askDoneCommand])
    }

    func testAskHookCommandFormats() {
        let path = "/Users/me/Library/Application Support/ClaudeItermMate/mate-notify.js"
        XCTAssertEqual(HookInstaller.askHookCommand(scriptPath: path), "node \"\(path)\" --event ask")
        XCTAssertEqual(HookInstaller.askDoneHookCommand(scriptPath: path), "node \"\(path)\" --event ask-done")
    }
}
