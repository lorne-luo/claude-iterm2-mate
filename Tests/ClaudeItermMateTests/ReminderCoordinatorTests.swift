import XCTest
@testable import ClaudeItermMate

@MainActor
final class ReminderCoordinatorTests: XCTestCase {
    final class SpyToast: ToastPanelProtocol {
        var shown: [String] = []
        var hidden = 0
        var hideIntoTab: [Bool] = []
        var lastOnClick: (() -> Void)?
        var lastOnHover: ((Bool) -> Void)?
        var lastOnMinimize: (() -> Void)?
        var lastOnClose: (() -> Void)?
        var lastShowsMinimize: Bool?
        func show(item: ReminderItem, on visible: CGRect, showsMinimize: Bool,
                  onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
                  onMinimize: @escaping () -> Void, onClose: @escaping () -> Void) {
            shown.append(item.sessionUUID)
            lastShowsMinimize = showsMinimize
            lastOnClick = onClick
            lastOnHover = onHover
            lastOnMinimize = onMinimize
            lastOnClose = onClose
        }
        func hide(intoTab: Bool) { hidden += 1; hideIntoTab.append(intoTab) }
    }

    struct StubProbe: ItermSessionProbe {
        let findable: Bool
        func canFind(_ uuid: String) -> Bool { findable }
    }

    private func payload(session: String = "S1", repoRoot: String = "/tmp/proj") -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: [
            "session_uuid": session, "cwd": repoRoot, "title": "[CC] proj",
            "summary": "done", "full_message": "done", "timestamp": 1.0,
            "repo_root": repoRoot,
        ]))!
    }

    private func coordinator(_ toast: SpyToast, duration: TimeInterval, findable: Bool = true) -> ReminderCoordinator {
        ReminderCoordinator(store: ReminderStore(), toastDuration: duration, toastPanel: toast,
                            probe: StubProbe(findable: findable))
    }

    /// `handle` probes iTerm2 off-main then presents on main — a yield lets that
    /// round-trip complete before asserting on the toast. These are wall-clock
    /// timing tests; margins are kept generous so scheduling jitter on slow/loaded
    /// CI runners does not flip an assertion (all timings scaled together).
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(240))
    }

    func testHandleShowsToastThenQueuesAfterDuration() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.4)
        coordinator.handle(payload())
        try await settle()
        XCTAssertEqual(toast.shown, ["S1"])
        XCTAssertTrue(coordinator.store.queued.isEmpty)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["S1"])
        XCTAssertEqual(toast.hidden, 1)
    }

    func testToastClickInvokesOnActivateWhenFindable() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 10)
        var activated: [String] = []
        coordinator.onActivate = { activated.append($0.sessionUUID) }
        coordinator.handle(payload(session: "S1"))
        try await settle()
        toast.lastOnClick?()
        XCTAssertEqual(activated, ["S1"])
    }

    func testUnfindableSessionOnlyToastsNoTabNoJump() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.4, findable: false)
        var activated: [String] = []
        coordinator.onActivate = { activated.append($0.sessionUUID) }
        coordinator.handle(payload())
        try await settle()
        XCTAssertEqual(toast.shown, ["S1"], "an unfindable session still toasts")
        toast.lastOnClick?()
        XCTAssertTrue(activated.isEmpty, "clicking an unfindable toast must not jump")
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(coordinator.store.queued.isEmpty, "unfindable session must not become a tab")
        XCTAssertTrue(coordinator.store.items.isEmpty, "unfindable item is dropped after the toast")
    }

    func testNewToastDemotesPreviousImmediately() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.8)
        // Distinct projects so both tabs coexist — dedup is per-project.
        coordinator.handle(payload(session: "A", repoRoot: "/tmp/alpha"))
        try await settle()
        coordinator.handle(payload(session: "B", repoRoot: "/tmp/beta"))
        try await settle()
        // B's arrival demoted A into a tab right away and B is now showing.
        XCTAssertEqual(toast.shown, ["A", "B"])
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["A"], "A is queued the moment B arrives")
        XCTAssertEqual(toast.hidden, 1, "A flew into the strip")
        // B then queues normally when its own countdown expires (A's cancelled
        // timer contributes nothing).
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(Set(coordinator.store.queued.map(\.sessionUUID)), ["A", "B"])
        XCTAssertEqual(toast.hidden, 2, "B flew into the strip on its own timer")
    }

    func testHoverPausesCountdownAndResumeQueues() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 1.2)
        coordinator.handle(payload())
        try await settle()
        toast.lastOnHover?(true) // pointer enters mid-countdown → pause
        try await Task.sleep(for: .milliseconds(2000)) // well past the 1.2 term
        XCTAssertTrue(coordinator.store.queued.isEmpty, "hover must pause the countdown")
        XCTAssertEqual(toast.hidden, 0, "paused toast must not fly away")
        toast.lastOnHover?(false) // pointer leaves → resume the remaining time
        try await Task.sleep(for: .milliseconds(1600))
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["S1"], "resume queues the tab")
    }

    func testReupsertRestartsToastCycle() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.8)
        coordinator.handle(payload())
        try await Task.sleep(for: .milliseconds(400))
        coordinator.handle(payload()) // same session mid-toast
        try await Task.sleep(for: .milliseconds(600))
        // first timer (due at 800ms) must not have queued the replaced item
        XCTAssertTrue(coordinator.store.queued.isEmpty)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(coordinator.store.queued.count, 1)
    }

    func testMinimizeQueuesImmediately() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.4)
        coordinator.handle(payload())
        try await settle()
        XCTAssertTrue(coordinator.store.queued.isEmpty)      // still toasting before minimize
        toast.lastOnMinimize?()                               // click the minimize button
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["S1"], "minimize queues the tab now")
        XCTAssertEqual(toast.hidden, 1, "minimize flies the toast into the strip")
        XCTAssertEqual(toast.hideIntoTab, [true], "minimize becomes a tab → shrink into the strip")
        // Past the original countdown: no duplicate queue, no second hide.
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["S1"])
        XCTAssertEqual(toast.hidden, 1)
    }

    func testMinimizeShownWhenFindable() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 10, findable: true)
        coordinator.handle(payload())
        try await settle()
        XCTAssertEqual(toast.lastShowsMinimize, true)
    }

    func testMinimizeHiddenWhenUnfindable() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 10, findable: false)
        coordinator.handle(payload())
        try await settle()
        XCTAssertEqual(toast.lastShowsMinimize, false)
    }

    func testCloseDismissesWithoutTab() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 10, findable: true)
        coordinator.handle(payload())
        try await settle()
        toast.lastOnClose?()                                  // click the close button
        XCTAssertTrue(coordinator.store.queued.isEmpty, "close must not queue a tab")
        XCTAssertTrue(coordinator.store.items.isEmpty, "close drops the item outright")
        XCTAssertEqual(toast.hidden, 1, "close still dismisses the toast")
        XCTAssertEqual(toast.hideIntoTab, [false], "close drops it → fade in place, no shrink-into-tab")
    }

    func testUnfindableTimerExpiryFadesWithoutShrink() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.4, findable: false)
        coordinator.handle(payload())
        try await settle()
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(coordinator.store.items.isEmpty, "unfindable session is dropped")
        XCTAssertEqual(toast.hideIntoTab, [false], "no tab to fly into → fade, not shrink")
    }

    func testTimerExpiryIntoTabShrinks() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.4, findable: true)
        coordinator.handle(payload())
        try await settle()
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["S1"])
        XCTAssertEqual(toast.hideIntoTab, [true], "became a tab → shrink into the strip")
    }

    private func sessionStartPayload(session: String = "S1", repoRoot: String = "/tmp/proj") -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: [
            "type": "session_start", "source": "startup",
            "session_uuid": session, "cwd": repoRoot, "title": "", "summary": "",
            "full_message": "", "timestamp": 1.0, "repo_root": repoRoot,
        ]))!
    }

    func testReminderTriggersUsageRefresh() async throws {
        let toast = SpyToast()
        let usage = UsageService(minInterval: 60, hudCachePath: "/nonexistent",
                                 now: { Date() },
                                 fetch: { _ in UsageSnapshot(
                                     fiveHour: UsageWindow(utilization: 55, resetsAt: nil),
                                     weekly: nil, weeklyOpus: nil) })
        let coordinator = ReminderCoordinator(store: ReminderStore(), toastDuration: 10,
                                              toastPanel: toast, probe: StubProbe(findable: true),
                                              usage: usage)
        coordinator.handle(payload())
        try await settle()
        try await Task.sleep(for: .milliseconds(50)) // let the fire-and-forget fetch land
        XCTAssertEqual(usage.snapshot?.fiveHour?.utilization, 55)
    }

    func testSessionStartProbesHudCache() {
        let path = NSTemporaryDirectory() + "coord-probe-\(UUID().uuidString).json"
        FileManager.default.createFile(atPath: path, contents: Data("{}".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let usage = UsageService(hudCachePath: path, fetch: { _ in nil })
        let coordinator = ReminderCoordinator(store: ReminderStore(), toastPanel: nil, usage: usage)
        coordinator.onSessionStart = { _, _ in }
        coordinator.handle(sessionStartPayload())
        XCTAssertTrue(usage.hudCacheAvailable, "session_start must probe the hud cache")
    }
}
