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
