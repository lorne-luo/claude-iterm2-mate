import XCTest
@testable import ClaudeItermMate

/// The session_start message path: payload decoding, coordinator routing to
/// the color injector, and SessionStart hook settings transforms.
final class SessionStartTests: XCTestCase {
    private func payload(_ json: [String: Any]) -> NotifyPayload? {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: json))
    }

    private let sessionStartJSON: [String: Any] = [
        "type": "session_start",
        "source": "startup",
        "session_uuid": "S1",
        "cwd": "/x/proj",
        "title": "",
        "summary": "",
        "full_message": "",
        "timestamp": 1.0,
        "repo_root": "/x/proj",
        "branch": "main",
    ]

    // MARK: payload

    func testSessionStartPayloadDecodes() {
        let p = payload(sessionStartJSON)
        XCTAssertNotNil(p)
        XCTAssertTrue(p!.isSessionStart)
        XCTAssertEqual(p!.source, "startup")
    }

    func testStopPayloadWithoutTypeIsNotSessionStart() {
        var json = sessionStartJSON
        json.removeValue(forKey: "type")
        json.removeValue(forKey: "source")
        let p = payload(json)
        XCTAssertNotNil(p)
        XCTAssertFalse(p!.isSessionStart)
        XCTAssertNil(p!.type)
    }

    // MARK: coordinator routing

    @MainActor
    func testSessionStartInjectsAssignedColorAndCreatesNoItem() {
        let store = ReminderStore()
        let coordinator = ReminderCoordinator(store: store, toastPanel: nil)
        var injected: [(session: String, name: String)] = []
        coordinator.onSessionStart = { injected.append(($0, $1)) }

        coordinator.handle(payload(sessionStartJSON)!)

        XCTAssertEqual(injected.count, 1)
        XCTAssertEqual(injected[0].session, "S1")
        XCTAssertEqual(injected[0].name, store.assigner.colorName(for: "/x/proj"))
        XCTAssertTrue(store.items.isEmpty, "session_start must not create a reminder")
    }

    @MainActor
    func testSessionStartColorMatchesLaterStopTabColor() {
        let store = ReminderStore()
        let coordinator = ReminderCoordinator(store: store, toastPanel: nil)
        var injectedName: String?
        coordinator.onSessionStart = { injectedName = $1 }

        coordinator.handle(payload(sessionStartJSON)!)

        var stopJSON = sessionStartJSON
        stopJSON.removeValue(forKey: "type")
        store.upsert(payload(stopJSON)!)

        let item = store.items[0]
        XCTAssertEqual(ReminderPalette.colorName(at: item.colorIndex), injectedName)
    }

    @MainActor
    func testWorktreeSessionStartRegistersLightenOrder() {
        let store = ReminderStore()
        let coordinator = ReminderCoordinator(store: store, toastPanel: nil)
        coordinator.onSessionStart = { _, _ in }

        var wt = sessionStartJSON
        wt["session_uuid"] = "S2"
        wt["cwd"] = "/x/proj-wt-a"
        wt["branch"] = "feat/a"
        wt["is_worktree"] = true
        coordinator.handle(payload(wt)!)

        // The stop-path item for the same worktree reuses the level registered
        // at session start (1 = first worktree of this repo).
        wt.removeValue(forKey: "type")
        store.upsert(payload(wt)!)
        XCTAssertEqual(store.items[0].lightenLevel, 1)
        XCTAssertEqual(store.items[0].colorIndex, store.assigner.colorIndex(for: "/x/proj"))
    }

    // MARK: installer settings transforms

    func testAddSessionStartHookAppendsAndIsIdempotent() {
        let cmd = "node \"/tmp/a b/mate-session-start.js\""
        let once = HookInstaller.settingsByAddingHook(
            [:], command: cmd, event: "SessionStart", marker: "mate-session-start.js"
        )
        let hooks = once["hooks"] as? [String: Any]
        let groups = hooks?["SessionStart"] as? [[String: Any]]
        XCTAssertEqual(groups?.count, 1)
        let entry = (groups?[0]["hooks"] as? [[String: Any]])?[0]
        XCTAssertEqual(entry?["command"] as? String, cmd)

        let twice = HookInstaller.settingsByAddingHook(
            once, command: cmd, event: "SessionStart", marker: "mate-session-start.js"
        )
        XCTAssertEqual(
            (twice["hooks"] as? [String: Any])?["SessionStart"] as? NSArray,
            (once["hooks"] as? [String: Any])?["SessionStart"] as? NSArray
        )
    }

    func testAddSessionStartHookPreservesStopHook() {
        let base = HookInstaller.settingsByAddingHook([:], command: "node \"/tmp/mate-notify.js\"")
        let both = HookInstaller.settingsByAddingHook(
            base,
            command: "node \"/tmp/mate-session-start.js\"",
            event: "SessionStart",
            marker: "mate-session-start.js"
        )
        let hooks = both["hooks"] as? [String: Any]
        XCTAssertEqual((hooks?["Stop"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((hooks?["SessionStart"] as? [[String: Any]])?.count, 1)
    }

    func testRemoveSessionStartHookLeavesOtherSessionStartHooks() {
        var settings = HookInstaller.settingsByAddingHook(
            [:], command: "other-tool --flag", event: "SessionStart", marker: "other-tool"
        )
        settings = HookInstaller.settingsByAddingHook(
            settings,
            command: "node \"/tmp/mate-session-start.js\"",
            event: "SessionStart",
            marker: "mate-session-start.js"
        )
        let removed = HookInstaller.settingsByRemovingHook(
            settings, event: "SessionStart", marker: "mate-session-start.js"
        )
        let groups = (removed["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]]
        XCTAssertEqual(groups?.count, 1)
        let entry = (groups?[0]["hooks"] as? [[String: Any]])?[0]
        XCTAssertEqual(entry?["command"] as? String, "other-tool --flag")
    }
}
