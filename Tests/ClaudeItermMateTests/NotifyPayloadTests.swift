import XCTest
@testable import ClaudeItermMate

final class NotifyPayloadTests: XCTestCase {
    private func json(_ overrides: [String: Any] = [:]) -> Data {
        var dict: [String: Any] = [
            "session_uuid": "ABC-123",
            "cwd": "/Users/me/Workspace/myproj",
            "title": "[CC] myproj",
            "summary": "Done",
            "full_message": "Done.\nAll tests pass.",
            "timestamp": 1234567890123.0,
        ]
        for (k, v) in overrides { dict[k] = v }
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    func testDecodesValidPayload() {
        let p = NotifyPayload.decode(json())
        XCTAssertEqual(p?.sessionUUID, "ABC-123")
        XCTAssertEqual(p?.fullMessage, "Done.\nAll tests pass.")
        XCTAssertEqual(p?.projectName, "myproj")
    }

    func testDecodesWithoutGitFields() {
        let p = NotifyPayload.decode(json())
        XCTAssertNil(p?.repoRoot)
        XCTAssertNil(p?.branch)
        XCTAssertEqual(p?.isWorktree, false)
    }

    func testDecodesWithGitFields() {
        let p = NotifyPayload.decode(json([
            "repo_root": "/Users/me/Workspace/myproj",
            "branch": "feature/auth",
            "is_worktree": true,
        ]))
        XCTAssertEqual(p?.repoRoot, "/Users/me/Workspace/myproj")
        XCTAssertEqual(p?.branch, "feature/auth")
        XCTAssertEqual(p?.isWorktree, true)
    }

    func testStatusAbsentDecodesAsCompleted() {
        let p = NotifyPayload.decode(json())
        XCTAssertNil(p?.status)
        XCTAssertEqual(p?.sessionStatus, .completed)
    }

    func testStatusWaitingDecodes() {
        let p = NotifyPayload.decode(json(["status": "waiting"]))
        XCTAssertEqual(p?.status, "waiting")
        XCTAssertEqual(p?.sessionStatus, .waiting)
    }

    func testStatusUnknownValueDecodesAsCompleted() {
        let p = NotifyPayload.decode(json(["status": "bogus"]))
        XCTAssertEqual(p?.sessionStatus, .completed)
    }

    func testStatusExplicitCompletedDecodes() {
        let p = NotifyPayload.decode(json(["status": "completed"]))
        XCTAssertEqual(p?.sessionStatus, .completed)
    }

    func testRejectsInvalidJSON() {
        XCTAssertNil(NotifyPayload.decode(Data("not json".utf8)))
    }

    func testRejectsEmptySessionUUID() {
        XCTAssertNil(NotifyPayload.decode(json(["session_uuid": ""])))
    }

    func testRejectsEmptyCwd() {
        XCTAssertNil(NotifyPayload.decode(json(["cwd": ""])))
    }

    func testRejectsOversizedPayload() {
        let big = String(repeating: "x", count: NotifyPayload.maxPayloadBytes)
        XCTAssertNil(NotifyPayload.decode(json(["full_message": big])))
    }
}
