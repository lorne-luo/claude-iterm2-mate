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

    func testDecodesQuestionPayload() {
        let p = NotifyPayload.decode(json([
            "type": "question",
            "status": "waiting",
            "questions": [
                [
                    "question": "Pick a color?",
                    "header": "Color",
                    "multiSelect": false,
                    "options": [
                        ["label": "Red", "description": "warm"],
                        ["label": "Blue", "description": "cool"],
                    ],
                ],
            ],
        ]))
        XCTAssertEqual(p?.isQuestion, true)
        XCTAssertEqual(p?.sessionStatus, .waiting)
        XCTAssertEqual(p?.questions?.count, 1)
        XCTAssertEqual(p?.questions?.first?.options.count, 2)
        XCTAssertEqual(p?.questions?.first?.options.first?.label, "Red")
        XCTAssertEqual(p?.questions?.first?.multiSelect, false)
    }

    func testStopTypeDecodesAsIsStop() {
        let p = NotifyPayload.decode(json(["type": "stop"]))
        XCTAssertEqual(p?.isStop, true)
        // A stop-marked reply that ends in a question is still a genuine Stop.
        let q = NotifyPayload.decode(json(["type": "stop", "status": "waiting"]))
        XCTAssertEqual(q?.isStop, true)
        XCTAssertEqual(q?.sessionStatus, .waiting)
    }

    func testTypelessPayloadIsNotStop() {
        // A permission-prompt Notification is type-less and must not read as a Stop.
        XCTAssertEqual(NotifyPayload.decode(json(["status": "waiting"]))?.isStop, false)
        XCTAssertEqual(NotifyPayload.decode(json())?.isStop, false)
    }

    func testDecodesMinimalResolvePayload() {
        // The `--event ask-done` payload has no title/summary/full_message.
        let data = try! JSONSerialization.data(withJSONObject: [
            "type": "resolve",
            "session_uuid": "ABC-123",
            "cwd": "/Users/me/Workspace/myproj",
            "timestamp": 1234567890123.0,
        ])
        let p = NotifyPayload.decode(data)
        XCTAssertEqual(p?.isResolve, true)
        XCTAssertEqual(p?.sessionUUID, "ABC-123")
        XCTAssertEqual(p?.summary, "")
        XCTAssertEqual(p?.fullMessage, "")
    }

    private func resolve(_ overrides: [String: Any] = [:]) -> NotifyPayload? {
        var dict: [String: Any] = [
            "type": "resolve",
            "session_uuid": "ABC-123",
            "cwd": "/Users/me/Workspace/myproj",
            "timestamp": 1234567890123.0,
        ]
        for (k, v) in overrides { dict[k] = v }
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: dict))
    }

    func testExitReasonDecodesAsSessionExit() {
        // `prompt_input_exit` is what a genuine quit emits — the only resetting
        // value of SessionEnd's four-value reason enum.
        let p = resolve(["end_reason": "prompt_input_exit"])
        XCTAssertEqual(p?.endReason, "prompt_input_exit")
        XCTAssertEqual(p?.isSessionExit, true)
    }

    func testNonExitReasonsAreNotSessionExit() {
        // `clear` keeps Claude alive; `logout`/`other` deliberately stay colored.
        for reason in ["clear", "logout", "other"] {
            XCTAssertEqual(resolve(["end_reason": reason])?.isSessionExit, false)
        }
    }

    func testResolveWithoutEndReasonIsNotSessionExit() {
        // The `--event ask-done` payload, and any resolve from a pre-feature hook.
        let p = resolve()
        XCTAssertEqual(p?.isResolve, true)
        XCTAssertNil(p?.endReason)
        XCTAssertEqual(p?.isSessionExit, false)
    }

    func testEndReasonOnANonResolveIsNotSessionExit() {
        XCTAssertEqual(
            NotifyPayload.decode(json(["end_reason": "prompt_input_exit"]))?.isSessionExit,
            false
        )
    }

    func testQuestionsAbsentByDefault() {
        XCTAssertNil(NotifyPayload.decode(json())?.questions)
        XCTAssertEqual(NotifyPayload.decode(json())?.isQuestion, false)
    }
}
