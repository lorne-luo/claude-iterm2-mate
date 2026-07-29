import XCTest
@testable import ClaudeItermMate

/// R8: coloring pre-existing sessions on Stop, with an in-memory hex-keyed dedup
/// shared by the SessionStart and Stop paths.
@MainActor
final class PaneColoringTests: XCTestCase {
    struct StubProbe: ItermSessionProbe {
        func canFind(_ uuid: String) -> Bool { false }
    }

    private func makeCoordinator() -> ReminderCoordinator {
        ReminderCoordinator(store: ReminderStore(), toastDuration: 0.1,
                            toastPanel: nil, probe: StubProbe())
    }

    private func stop(session: String = "CC-1", repo: String = "/tmp/proj",
                      branch: String = "main", isWorktree: Bool = false,
                      focusable: Bool = true) -> NotifyPayload {
        var json: [String: Any] = [
            "session_uuid": session, "cwd": repo, "title": "t", "summary": "s",
            "full_message": "m", "timestamp": 1.0, "repo_root": repo, "branch": branch,
        ]
        if isWorktree { json["is_worktree"] = true }
        if !focusable { json["focusable"] = false }
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: json))!
    }

    private func sessionStart(session: String = "CC-1", repo: String = "/tmp/proj",
                              branch: String = "main") -> NotifyPayload {
        let json: [String: Any] = [
            "type": "session_start", "source": "startup", "session_uuid": session,
            "cwd": repo, "title": "", "summary": "", "full_message": "", "timestamp": 1.0,
            "repo_root": repo, "branch": branch,
        ]
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: json))!
    }

    func testStopColorsUncoloredSessionOnceThenDedups() {
        let coordinator = makeCoordinator()
        var applied: [(String, String)] = []
        coordinator.onSetPaneBackground = { applied.append(($0, $1)) }

        coordinator.handle(stop())
        XCTAssertEqual(applied.count, 1, "first Stop colors a pre-existing session")
        XCTAssertEqual(applied[0].0, "CC-1")

        coordinator.handle(stop())
        XCTAssertEqual(applied.count, 1, "identical second Stop is a no-op (hex dedup)")
    }

    func testStopReappliesWhenProjectHexChanges() {
        let coordinator = makeCoordinator()
        var applied: [(String, String)] = []
        coordinator.onSetPaneBackground = { applied.append(($0, $1)) }

        // Same session, same repo (same slot) but mainline → worktree changes the
        // shade, so the hex differs and must re-apply.
        coordinator.handle(stop(session: "S", repo: "/r", branch: "main", isWorktree: false))
        coordinator.handle(stop(session: "S", repo: "/r", branch: "feature/x", isWorktree: true))
        XCTAssertEqual(applied.count, 2, "a changed project hex re-applies")
        XCTAssertNotEqual(applied[0].1, applied[1].1)
    }

    func testDisabledStopColorsNothingAndDoesNotRecord() {
        let coordinator = makeCoordinator()
        var applied: [(String, String)] = []
        coordinator.onSetPaneBackground = { applied.append(($0, $1)) }

        coordinator.isPaneColoringEnabled = { false }
        coordinator.handle(stop())
        XCTAssertEqual(applied.count, 0, "disabled → no coloring")

        // Enabling later must color on the next Stop (nothing was recorded).
        coordinator.isPaneColoringEnabled = { true }
        coordinator.handle(stop())
        XCTAssertEqual(applied.count, 1, "re-enabling colors on the next Stop")
    }

    func testNonFocusableStopNeverColors() {
        let coordinator = makeCoordinator()
        var applied = 0
        coordinator.onSetPaneBackground = { _, _ in applied += 1 }

        coordinator.handle(stop(focusable: false))
        XCTAssertEqual(applied, 0, "non-iTerm2 session has no pane to color")
    }

    private func resolve(session: String = "CC-1", endReason: String? = nil) -> NotifyPayload {
        var json: [String: Any] = [
            "type": "resolve", "session_uuid": session, "cwd": "/tmp/proj", "timestamp": 1.0,
        ]
        if let endReason { json["end_reason"] = endReason }
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: json))!
    }

    func testEachSessionExitResetsPaneBackground() {
        let coordinator = makeCoordinator()
        var reset: [String] = []
        coordinator.onResetPaneBackground = { reset.append($0) }

        coordinator.handle(resolve(session: "S", endReason: "exit"))
        coordinator.handle(resolve(session: "S", endReason: "prompt_input_exit"))
        XCTAssertEqual(reset, ["S", "S"], "each genuine exit resets that session's pane")
    }

    func testNonExitResolveNeverResetsPaneBackground() {
        let coordinator = makeCoordinator()
        var reset = 0
        coordinator.onResetPaneBackground = { _ in reset += 1 }

        // `/clear` keeps Claude alive (and is followed by a SessionStart);
        // logout/other stay colored on purpose; an absent reason is an
        // AskUserQuestion answer or a pre-feature hook.
        coordinator.handle(resolve(endReason: "clear"))
        coordinator.handle(resolve(endReason: "logout"))
        coordinator.handle(resolve(endReason: "other"))
        coordinator.handle(resolve())
        XCTAssertEqual(reset, 0)
    }

    func testDisabledColoringNeverResetsPaneBackground() {
        let coordinator = makeCoordinator()
        var reset = 0
        coordinator.onResetPaneBackground = { _ in reset += 1 }

        coordinator.isPaneColoringEnabled = { false }
        coordinator.handle(resolve(endReason: "exit"))
        XCTAssertEqual(reset, 0, "never colored → nothing to reset")
    }

    func testSessionStartAfterExitRecolorsTheSamePane() {
        let coordinator = makeCoordinator()
        var applied: [(String, String)] = []
        coordinator.onSetPaneBackground = { applied.append(($0, $1)) }
        coordinator.onResetPaneBackground = { _ in }

        coordinator.handle(sessionStart(session: "S", repo: "/r", branch: "main"))
        XCTAssertEqual(applied.count, 1)
        coordinator.handle(resolve(session: "S", endReason: "exit"))
        // The exit must clear the hex memory, or `colorPaneIfNeeded`'s dedup would
        // leave the restarted session sitting at the default background.
        coordinator.handle(sessionStart(session: "S", repo: "/r", branch: "main"))
        XCTAssertEqual(applied.count, 2, "a restarted session in the same pane re-colors")
        XCTAssertEqual(applied[0].1, applied[1].1)
    }

    /// A genuine Stop (type "stop") — the only event that injects `/color`.
    private func genuineStop(session: String = "CC-1", repo: String = "/tmp/proj") -> NotifyPayload {
        let json: [String: Any] = [
            "type": "stop", "session_uuid": session, "cwd": repo, "title": "t",
            "summary": "s", "full_message": "m", "timestamp": 1.0, "repo_root": repo,
            "branch": "main",
        ]
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: json))!
    }

    func testStopAfterExitReinjectsColorInTheSamePane() {
        let coordinator = makeCoordinator()
        var injected: [(String, String)] = []
        coordinator.onInjectColor = { injected.append(($0, $1)) }
        coordinator.onSetPaneBackground = { _, _ in }
        coordinator.onResetPaneBackground = { _ in }

        coordinator.handle(genuineStop(session: "S", repo: "/r"))
        XCTAssertEqual(injected.count, 1)
        coordinator.handle(resolve(session: "S", endReason: "exit"))
        // The exit must clear the inject-once flag too, or the restarted session's
        // pane would re-color while its prompt bar stayed default.
        coordinator.handle(sessionStart(session: "S", repo: "/r", branch: "main"))
        coordinator.handle(genuineStop(session: "S", repo: "/r"))
        XCTAssertEqual(injected.count, 2, "a restarted session in the same pane re-injects /color")
        XCTAssertEqual(injected.map(\.0), ["S", "S"])
        XCTAssertEqual(injected.first?.1, injected.last?.1)
    }

    func testSessionStartDedupsWithFollowingStop() {
        let coordinator = makeCoordinator()
        var applied: [(String, String)] = []
        coordinator.onSetPaneBackground = { applied.append(($0, $1)) }

        coordinator.handle(sessionStart(session: "S", repo: "/r", branch: "main"))
        XCTAssertEqual(applied.count, 1, "SessionStart colors once")
        coordinator.handle(stop(session: "S", repo: "/r", branch: "main"))
        XCTAssertEqual(applied.count, 1, "a Stop with the same hex does not re-color")
    }
}
