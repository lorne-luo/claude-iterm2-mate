import XCTest
@testable import ClaudeItermMate

/// Non-iTerm2 (non-focusable) sessions: payload decoding and the coordinator's
/// toggle-driven "desktop notification vs silent" routing. Non-iTerm2 sessions
/// never become tabs (no pane to jump to).
@MainActor
final class NonItermSessionTests: XCTestCase {
    final class SpyToast: ToastPanelProtocol {
        var shown: [String] = []
        var hidden = 0
        var hideIntoTab: [Bool] = []
        var lastOnClick: (() -> Void)?
        func show(item: ReminderItem, on visible: CGRect, showsMinimize: Bool,
                  onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
                  onMinimize: @escaping () -> Void, onClose: @escaping () -> Void,
                  onAnswer: @escaping (ItermSendTextAction.Answer, Int) -> Void,
                  onChat: @escaping () -> Void) {
            shown.append(item.sessionUUID)
            lastOnClick = onClick
        }
        func hide(intoTab: Bool) { hidden += 1; hideIntoTab.append(intoTab) }
    }

    struct StubProbe: ItermSessionProbe {
        func canFind(_ uuid: String) -> Bool { false } // no iTerm2 session exists
    }

    private func payload(focusable: Bool, session: String = "CC-1",
                         summary: String = "done", full: String = "done") -> NotifyPayload {
        var json: [String: Any] = [
            "session_uuid": session, "cwd": "/tmp/proj", "title": "[CC] proj",
            "summary": summary, "full_message": full, "timestamp": 1.0, "repo_root": "/tmp/proj",
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

    func testNonItermNotifiesWhenToggleOn() async throws {
        let toast = SpyToast()
        let coordinator = makeCoordinator(toast)
        coordinator.isNonItermEnabled = { true }
        var notified: [(String, String, String)] = []
        coordinator.onNotify = { notified.append(($0, $1, $2)) }

        coordinator.handle(payload(focusable: false, summary: "first",
                                   full: "first\nmore body text"))
        XCTAssertTrue(toast.shown.isEmpty, "non-iTerm2 session never becomes a toast/tab")
        XCTAssertEqual(notified.count, 1, "toggle on → desktop notification")
        XCTAssertEqual(notified[0].0, "[CC] proj", "title is the payload title")
        XCTAssertEqual(notified[0].1, "first", "subtitle is the summary")
        XCTAssertEqual(notified[0].2, "more body text", "body is the reply past its first line")

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(coordinator.store.items.isEmpty, "no tab stored")
    }

    func testNonItermSilentWhenToggleOff() async throws {
        let toast = SpyToast()
        let coordinator = makeCoordinator(toast)
        coordinator.isNonItermEnabled = { false }
        var notified = 0
        coordinator.onNotify = { _, _, _ in notified += 1 }

        coordinator.handle(payload(focusable: false))
        XCTAssertTrue(toast.shown.isEmpty, "no tab/toast when the toggle is off")
        XCTAssertEqual(notified, 0, "no desktop notification when the toggle is off")
        XCTAssertTrue(coordinator.store.items.isEmpty)
    }

    func testFocusableSessionUnaffectedByToggle() async throws {
        let toast = SpyToast()
        let coordinator = makeCoordinator(toast) // probe says unfindable
        coordinator.isNonItermEnabled = { false }
        var notified = 0
        coordinator.onNotify = { _, _, _ in notified += 1 }

        coordinator.handle(payload(focusable: true))
        try await Task.sleep(for: .milliseconds(240))
        // Focusable path ignores the non-iTerm toggle entirely and takes the
        // normal probe route (here unfindable → toast only, never a notification).
        XCTAssertEqual(toast.shown, ["CC-1"])
        XCTAssertEqual(notified, 0, "focusable path never fires a desktop notification")
    }

    func testNotificationBodyMultiLine() {
        XCTAssertEqual(
            ReminderCoordinator.notificationBody("first line\nsecond\nthird"),
            "second third",
            "reply past the first line, whitespace-flattened"
        )
    }

    func testNotificationBodySingleLineIsEmpty() {
        XCTAssertEqual(ReminderCoordinator.notificationBody("only one line"), "",
                       "single-line reply has no extra body")
    }

    func testNotificationBodyTruncates() {
        let long = "head\n" + String(repeating: "x", count: 300)
        let body = ReminderCoordinator.notificationBody(long, limit: 200)
        XCTAssertEqual(body.count, 201, "200 chars + ellipsis")
        XCTAssertTrue(body.hasSuffix("…"))
    }
}
