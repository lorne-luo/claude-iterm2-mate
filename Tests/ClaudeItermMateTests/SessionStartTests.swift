import XCTest
@testable import ClaudeItermMate

/// The session_start message path: payload decoding, coordinator routing to
/// the pane colorer, and SessionStart hook settings transforms.
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
    func testSessionStartSetsPaneBackgroundAndCreatesNoItem() {
        let store = ReminderStore()
        let coordinator = ReminderCoordinator(store: store, toastPanel: nil)
        var applied: [(session: String, hex: String)] = []
        coordinator.onSetPaneBackground = { applied.append(($0, $1)) }

        coordinator.handle(payload(sessionStartJSON)!)

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied[0].session, "S1")
        // branch "main", not a worktree → shade 0.
        let idx = store.assigner.colorIndex(for: "/x/proj")
        XCTAssertEqual(applied[0].hex, ReminderPalette.backgroundHex(at: idx, shade: 0))
        XCTAssertTrue(store.items.isEmpty, "session_start must not create a reminder")
    }

    @MainActor
    func testSessionStartColorMatchesLaterStopTabColor() {
        let store = ReminderStore()
        let coordinator = ReminderCoordinator(store: store, toastPanel: nil)
        var appliedHex: String?
        coordinator.onSetPaneBackground = { appliedHex = $1 }

        coordinator.handle(payload(sessionStartJSON)!)

        var stopJSON = sessionStartJSON
        stopJSON.removeValue(forKey: "type")
        store.upsert(payload(stopJSON)!)

        // The pane background is the dark variant of the same slot the tab uses.
        let item = store.items[0]
        XCTAssertEqual(ReminderPalette.backgroundHex(at: item.colorIndex, shade: 0), appliedHex)
    }

    @MainActor
    func testSessionStartDoesNotSetLightenLevel() {
        let store = ReminderStore()
        let coordinator = ReminderCoordinator(store: store, toastPanel: nil)
        coordinator.onSetPaneBackground = { _, _ in }

        // session_start injects a color but registers no tab, so a lone stop-path
        // session in the same directory renders at the base level (0). The color
        // slot still matches the assigner.
        coordinator.handle(payload(sessionStartJSON)!)

        var stopJSON = sessionStartJSON
        stopJSON.removeValue(forKey: "type")
        store.upsert(payload(stopJSON)!)
        XCTAssertEqual(store.items[0].lightenLevel, 0)
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
