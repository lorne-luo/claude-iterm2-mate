import XCTest
@testable import ClaudeItermMate

@MainActor
final class ReminderCoordinatorTests: XCTestCase {
    final class SpyToast: ToastPanelProtocol {
        var shown: [String] = []
        var hidden = 0
        func show(item: ReminderItem, on visible: CGRect) { shown.append(item.sessionUUID) }
        func hide() { hidden += 1 }
    }

    private func payload(session: String = "S1") -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: [
            "session_uuid": session, "cwd": "/tmp/proj", "title": "[CC] proj",
            "summary": "done", "full_message": "done", "timestamp": 1.0,
        ]))!
    }

    func testHandleShowsToastThenQueuesAfterDuration() async throws {
        let store = ReminderStore()
        let toast = SpyToast()
        let coordinator = ReminderCoordinator(store: store, toastDuration: 0.1, toastPanel: toast)
        coordinator.handle(payload())
        XCTAssertEqual(toast.shown, ["S1"])
        XCTAssertTrue(store.queued.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(store.queued.map(\.sessionUUID), ["S1"])
        XCTAssertEqual(toast.hidden, 1)
    }

    func testOlderSessionTimerDoesNotHideNewerToast() async throws {
        let store = ReminderStore()
        let toast = SpyToast()
        let coordinator = ReminderCoordinator(store: store, toastDuration: 0.2, toastPanel: toast)
        coordinator.handle(payload(session: "A"))
        try await Task.sleep(for: .milliseconds(100))
        coordinator.handle(payload(session: "B")) // different session, mid-A-toast
        // Wait past A's timer (~0.2) but before B's timer (~0.3).
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(toast.shown, ["A", "B"])
        XCTAssertEqual(toast.hidden, 0, "A's expiring timer must not hide B's visible toast")
        XCTAssertEqual(store.queued.map(\.sessionUUID), ["A"], "A should be queued once its toast expires")
        // Wait past B's timer.
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(toast.hidden, 1, "B's own timer hides B's toast")
        XCTAssertEqual(Set(store.queued.map(\.sessionUUID)), ["A", "B"])
    }

    func testReupsertRestartsToastCycle() async throws {
        let store = ReminderStore()
        let toast = SpyToast()
        let coordinator = ReminderCoordinator(store: store, toastDuration: 0.2, toastPanel: toast)
        coordinator.handle(payload())
        try await Task.sleep(for: .milliseconds(100))
        coordinator.handle(payload()) // same session mid-toast
        try await Task.sleep(for: .milliseconds(150))
        // first timer (due at 200ms) must not have queued the replaced item
        XCTAssertTrue(store.queued.isEmpty)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.queued.count, 1)
    }
}
