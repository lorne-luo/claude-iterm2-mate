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

    /// Probe with a mutable live set for reconcile tests. `live == nil` models a
    /// failed/unavailable query (reconcile must skip GC); `findableWhenUnknown`
    /// lets a nil-live test still build tabs so we can assert they are retained.
    /// Read off-main, mutated on main between serialized `settle()`s — safe under
    /// the tests' timing, hence `@unchecked Sendable`.
    final class ReconcileProbe: ItermSessionProbe, @unchecked Sendable {
        var live: Set<String>?
        let findableWhenUnknown: Bool
        init(live: Set<String>?, findableWhenUnknown: Bool = true) {
            self.live = live
            self.findableWhenUnknown = findableWhenUnknown
        }
        func canFind(_ uuid: String) -> Bool { live?.contains(uuid) ?? findableWhenUnknown }
        func liveSessionIDs() -> Set<String>? { live }
    }

    private func payload(session: String = "S1", repoRoot: String = "/tmp/proj") -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: [
            "session_uuid": session, "cwd": repoRoot, "title": "[CC] proj",
            "summary": "done", "full_message": "done", "timestamp": 1.0,
            "repo_root": repoRoot, "type": "stop",
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

    private func waitingPayload(session: String = "S1", repoRoot: String = "/tmp/proj",
                               full: String = "waiting") -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: [
            "session_uuid": session, "cwd": repoRoot, "title": "[CC] proj",
            "summary": "waiting", "full_message": full, "timestamp": 1.0,
            "repo_root": repoRoot, "status": "waiting",
        ]))!
    }

    func testWaitingFirstToastsAndMarksStatus() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 10)
        coordinator.handle(waitingPayload())
        try await settle()
        XCTAssertEqual(toast.shown, ["S1"])
        XCTAssertEqual(coordinator.store.items.first?.status, .waiting)
    }

    // AC6: a permission storm (repeated waiting for one session) must refresh the
    // existing tab, not spawn a second toast.
    func testWaitingDoesNotRetoastWhileQueued() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.4)
        coordinator.handle(waitingPayload(full: "perm Bash"))
        try await settle()
        try await Task.sleep(for: .milliseconds(1200)) // let it queue
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["S1"])
        XCTAssertEqual(toast.shown, ["S1"])

        coordinator.handle(waitingPayload(full: "perm Write"))
        try await settle()
        XCTAssertEqual(toast.shown, ["S1"], "a follow-up waiting must not re-toast")
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["S1"])
        XCTAssertEqual(coordinator.store.queued.first?.status, .waiting)
        XCTAssertEqual(coordinator.store.queued.first?.fullMessage, "perm Write",
                       "the existing tab's content is refreshed in place")
    }

    // AC5 (coordinator half): a real completion after a waiting tab re-toasts and
    // flips the tab to completed (amber clears).
    func testCompletedAfterWaitingRetoastsAndFlipsStatus() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.4)
        coordinator.handle(waitingPayload())
        try await settle()
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(coordinator.store.queued.first?.status, .waiting)

        coordinator.handle(payload()) // no status → completed
        try await settle()
        XCTAssertEqual(toast.shown, ["S1", "S1"], "a genuine completion re-toasts")
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(coordinator.store.queued.first?.status, .completed, "flipped to completed")
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
        coordinator.onSetPaneBackground = { _, _ in }
        coordinator.handle(sessionStartPayload())
        XCTAssertTrue(usage.hudCacheAvailable, "session_start must probe the hud cache")
    }

    // MARK: - AskUserQuestion

    private func decode(_ dict: [String: Any]) -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: dict))!
    }

    private func questionPayload(session: String = "S1") -> NotifyPayload {
        decode([
            "session_uuid": session, "cwd": "/tmp/proj", "title": "proj",
            "summary": "Pick?", "full_message": "Pick?", "timestamp": 1.0,
            "type": "question", "status": "waiting",
            "questions": [[
                "question": "Pick?", "header": "H", "multiSelect": false,
                "options": [["label": "A", "description": ""], ["label": "B", "description": ""]],
            ]],
        ])
    }

    func testResolveRemovesTab() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.2)
        coordinator.handle(questionPayload())
        try await settle()
        XCTAssertEqual(coordinator.store.items.count, 1)
        XCTAssertEqual(coordinator.store.items.first?.kind, .question)

        coordinator.handle(decode([
            "session_uuid": "S1", "cwd": "/tmp/proj", "timestamp": 2.0, "type": "resolve",
        ]))
        XCTAssertTrue(coordinator.store.items.isEmpty, "resolve must remove the tab")
    }

    func testQuestionNotOverwrittenByGenericPermissionWaiting() async throws {
        let toast = SpyToast()
        let coordinator = coordinator(toast, duration: 0.2)
        coordinator.handle(questionPayload())
        try await settle()

        // The generic permission_prompt Notification for the same session must
        // not clobber the rich question tab.
        coordinator.handle(decode([
            "session_uuid": "S1", "cwd": "/tmp/proj", "title": "proj",
            "summary": "Claude needs your permission",
            "full_message": "Claude needs your permission",
            "timestamp": 3.0, "status": "waiting",
        ]))
        try await settle()

        let item = coordinator.store.items.first
        XCTAssertEqual(item?.kind, .question)
        XCTAssertEqual(item?.summary, "Pick?", "generic waiting must not overwrite the question")
        XCTAssertEqual(item?.questions.count, 1)
    }

    // MARK: - /color injection on Stop

    /// The color name expected for a repo, resolved via the same assigner the
    /// coordinator uses (stable/idempotent).
    private func expectedColorName(_ coordinator: ReminderCoordinator, repoRoot: String) -> String {
        let identity = ReminderIdentity(repoRoot: repoRoot, branch: nil, cwd: repoRoot)
        return ReminderPalette.colorName(at: coordinator.store.assigner.colorIndex(for: identity.key))
    }

    /// A genuine Stop (type "stop") whose reply ends in a question — still an
    /// ordinary composer, so injection is safe and expected.
    private func waitingStopPayload(session: String = "S1", repoRoot: String = "/tmp/proj") -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: [
            "session_uuid": session, "cwd": repoRoot, "title": "[CC] proj",
            "summary": "?", "full_message": "Which one?", "timestamp": 1.0,
            "repo_root": repoRoot, "type": "stop", "status": "waiting",
        ]))!
    }

    // A completed, focusable Stop injects /color once; a second Stop for the
    // same session does not re-inject (boolean per-session dedup).
    func testCompletedStopInjectsColorOncePerSession() {
        let coordinator = coordinator(SpyToast(), duration: 10)
        var injected: [(String, String)] = []
        coordinator.onInjectColor = { injected.append(($0, $1)) }
        coordinator.handle(payload())
        XCTAssertEqual(injected.map(\.0), ["S1"])
        XCTAssertEqual(injected.first?.1, expectedColorName(coordinator, repoRoot: "/tmp/proj"))
        coordinator.handle(payload())
        XCTAssertEqual(injected.count, 1, "same session must not re-inject")
    }

    // A genuine Stop whose reply ends in a question is still injected — the
    // composer is ordinary; only the TUI-bearing events below are excluded.
    func testWaitingGenuineStopInjectsColor() {
        let coordinator = coordinator(SpyToast(), duration: 10)
        var injected: [String] = []
        coordinator.onInjectColor = { session, _ in injected.append(session) }
        coordinator.handle(waitingStopPayload())
        XCTAssertEqual(injected, ["S1"], "a question-ending Stop still injects /color")
    }

    // A permission-prompt Notification (type-less, waiting) is NOT a Stop and
    // must not inject — its live TUI would be corrupted by the keys.
    func testPermissionNotificationDoesNotInjectColor() {
        let coordinator = coordinator(SpyToast(), duration: 10)
        var injected: [String] = []
        coordinator.onInjectColor = { session, _ in injected.append(session) }
        coordinator.handle(waitingPayload())
        XCTAssertTrue(injected.isEmpty, "a permission notification must not inject /color")
    }

    // An AskUserQuestion event (type "question") must not inject — same TUI risk.
    func testQuestionEventDoesNotInjectColor() {
        let coordinator = coordinator(SpyToast(), duration: 10)
        var injected: [String] = []
        coordinator.onInjectColor = { session, _ in injected.append(session) }
        coordinator.handle(questionPayload())
        XCTAssertTrue(injected.isEmpty, "an AskUserQuestion must not inject /color")
    }

    // SessionStart must not inject (injection is Stop-only).
    func testSessionStartDoesNotInjectColor() {
        let coordinator = ReminderCoordinator(store: ReminderStore(), toastPanel: nil)
        var injected: [String] = []
        coordinator.onInjectColor = { session, _ in injected.append(session) }
        coordinator.onSetPaneBackground = { _, _ in }
        coordinator.handle(sessionStartPayload())
        XCTAssertTrue(injected.isEmpty, "session_start must not inject /color")
    }

    // AC7: with coloring disabled, no injection and the session stays unmarked, so
    // enabling later injects on the next completed Stop.
    func testDisabledGateSkipsInjectionAndDoesNotMark() {
        let coordinator = coordinator(SpyToast(), duration: 10)
        var injected: [String] = []
        coordinator.onInjectColor = { session, _ in injected.append(session) }
        coordinator.isPaneColoringEnabled = { false }
        coordinator.handle(payload())
        XCTAssertTrue(injected.isEmpty, "disabled gate must skip injection")
        coordinator.isPaneColoringEnabled = { true }
        coordinator.handle(payload())
        XCTAssertEqual(injected, ["S1"], "session was not marked while disabled → injects once enabled")
    }

    // MARK: - Reconcile GC of closed iTerm2 sessions

    // R8: a reminder event whose live set omits a prior session GCs that dead
    // tab; a session still in the set is retained.
    func testReconcileRemovesDeadTabKeepsLive() async throws {
        let toast = SpyToast()
        let probe = ReconcileProbe(live: ["A", "B"])
        let coordinator = ReminderCoordinator(store: ReminderStore(), toastDuration: 0.3,
                                              toastPanel: toast, probe: probe)
        coordinator.handle(payload(session: "A"))
        try await settle()
        try await Task.sleep(for: .milliseconds(400)) // A demotes to a queued tab
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["A"])

        probe.live = ["B"] // A's pane is closed, set before the next event
        coordinator.handle(payload(session: "B"))
        try await settle()
        XCTAssertFalse(coordinator.store.items.contains { $0.sessionUUID == "A" },
                       "closed pane's dead tab is reconciled away")
        XCTAssertTrue(coordinator.store.items.contains { $0.sessionUUID == "B" },
                      "live session B is retained")
    }

    // Decision: when the live set is unknown (probe failure), reconcile is
    // skipped — a live tab must NOT be wiped by a transient it2 failure.
    func testReconcileSkippedWhenLiveSetUnknown() async throws {
        let toast = SpyToast()
        let probe = ReconcileProbe(live: nil, findableWhenUnknown: true)
        let coordinator = ReminderCoordinator(store: ReminderStore(), toastDuration: 0.3,
                                              toastPanel: toast, probe: probe)
        coordinator.handle(payload(session: "A"))
        try await settle()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(coordinator.store.queued.map(\.sessionUUID), ["A"])

        coordinator.handle(payload(session: "B"))
        try await settle()
        XCTAssertTrue(coordinator.store.items.contains { $0.sessionUUID == "A" },
                      "nil live set must not GC an existing tab")
    }

    // R7: a closed session's color hex + inject-once flag are GC'd, so if the
    // same session id reappears it re-colors and re-injects.
    func testReconcileClearsColorAndInjectFlags() async throws {
        let toast = SpyToast()
        let probe = ReconcileProbe(live: ["A", "B"])
        let coordinator = ReminderCoordinator(store: ReminderStore(), toastDuration: 10,
                                              toastPanel: toast, probe: probe)
        var injected: [String] = []
        var colored: [String] = []
        coordinator.onInjectColor = { session, _ in injected.append(session) }
        coordinator.onSetPaneBackground = { session, _ in colored.append(session) }

        coordinator.handle(payload(session: "A"))
        try await settle()
        probe.live = ["B"] // A closed, set before the next event drops its flags
        coordinator.handle(payload(session: "B"))
        try await settle()
        probe.live = ["A", "B"] // A reappears (same id), set before its re-event
        coordinator.handle(payload(session: "A"))
        try await settle()

        XCTAssertEqual(injected.filter { $0 == "A" }.count, 2,
                       "A's inject-once flag was GC'd, so it injects again")
        XCTAssertEqual(colored.filter { $0 == "A" }.count, 2,
                       "A's color hex was GC'd, so it colors again")
    }
}
