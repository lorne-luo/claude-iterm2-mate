import XCTest
@testable import ClaudeItermMate

/// Non-iTerm2 (non-focusable) sessions: payload decoding and the coordinator's
/// toggle-driven "tab vs desktop notification" routing.
@MainActor
final class NonItermSessionTests: XCTestCase {
    final class SpyToast: ToastPanelProtocol {
        var shown: [String] = []
        var hidden = 0
        var hideIntoTab: [Bool] = []
        var lastOnClick: (() -> Void)?
        func show(item: ReminderItem, on visible: CGRect, showsMinimize: Bool,
                  onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
                  onMinimize: @escaping () -> Void, onClose: @escaping () -> Void) {
            shown.append(item.sessionUUID)
            lastOnClick = onClick
        }
        func hide(intoTab: Bool) { hidden += 1; hideIntoTab.append(intoTab) }
    }

    struct StubProbe: ItermSessionProbe {
        func canFind(_ uuid: String) -> Bool { false } // no iTerm2 session exists
    }

    private func payload(focusable: Bool, session: String = "CC-1") -> NotifyPayload {
        var json: [String: Any] = [
            "session_uuid": session, "cwd": "/tmp/proj", "title": "[CC] proj",
            "summary": "done", "full_message": "done", "timestamp": 1.0, "repo_root": "/tmp/proj",
        ]
        if !focusable { json["focusable"] = false }
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: json))!
    }

    private func makeCoordinator(_ toast: SpyToast) -> ReminderCoordinator {
        ReminderCoordinator(store: ReminderStore(), toastDuration: 0.3,
                            toastPanel: toast, probe: StubProbe())
    }

    func testFocusableDefaultsTrueWhenAbsent() {
        XCTAssertTrue(payload(focusable: true).focusable)
    }

    func testFocusableFalseDecodes() {
        XCTAssertFalse(payload(focusable: false).focusable)
    }

    func testNonItermBecomesTabWhenToggleOn() async throws {
        let toast = SpyToast()
        let coordinator = makeCoordinator(toast)
        coordinator.isNonItermEnabled = { true }
        var notified: [(String, String)] = []
        coordinator.onNotify = { notified.append(($0, $1)) }

        coordinator.handle(payload(focusable: false))
        XCTAssertEqual(toast.shown, ["CC-1"], "non-iTerm2 session toasts even though unfindable")
        XCTAssertTrue(notified.isEmpty, "no desktop notification when the toggle is on")

        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["CC-1"], "it becomes a tab")
    }

    func testNonItermClickDismissesWithoutJump() async throws {
        let toast = SpyToast()
        let coordinator = makeCoordinator(toast)
        coordinator.isNonItermEnabled = { true }
        var activated: [ReminderItem] = []
        coordinator.onActivate = { activated.append($0) }

        coordinator.handle(payload(focusable: false))
        toast.lastOnClick?()
        XCTAssertEqual(activated.map(\.sessionUUID), ["CC-1"])
        XCTAssertFalse(activated[0].focusable, "click routes through onActivate but the item is non-focusable")
    }

    func testNonItermFallsBackToNotificationWhenToggleOff() async throws {
        let toast = SpyToast()
        let coordinator = makeCoordinator(toast)
        coordinator.isNonItermEnabled = { false }
        var notified: [(String, String)] = []
        coordinator.onNotify = { notified.append(($0, $1)) }

        coordinator.handle(payload(focusable: false))
        XCTAssertTrue(toast.shown.isEmpty, "no tab/toast when the toggle is off")
        XCTAssertEqual(notified.count, 1)
        XCTAssertEqual(notified[0].0, "[CC] proj")
        XCTAssertTrue(coordinator.store.items.isEmpty)
    }

    func testFocusableSessionUnaffectedByToggle() async throws {
        let toast = SpyToast()
        let coordinator = makeCoordinator(toast) // probe says unfindable
        coordinator.isNonItermEnabled = { false }
        var notified = 0
        coordinator.onNotify = { _, _ in notified += 1 }

        coordinator.handle(payload(focusable: true))
        try await Task.sleep(for: .milliseconds(240))
        // Focusable path ignores the non-iTerm toggle entirely and takes the
        // normal probe route (here unfindable → toast only, no notification).
        XCTAssertEqual(toast.shown, ["CC-1"])
        XCTAssertEqual(notified, 0)
    }
}
