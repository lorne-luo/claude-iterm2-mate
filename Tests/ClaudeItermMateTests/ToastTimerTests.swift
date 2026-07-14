import XCTest
@testable import ClaudeItermMate

@MainActor
final class ToastTimerTests: XCTestCase {
    func testFiresAfterDuration() async throws {
        var fired = 0
        let t = ToastTimer(duration: 0.15) { fired += 1 }
        t.start()
        XCTAssertEqual(fired, 0)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fired, 1)
    }

    func testPausePreventsFireAndResumeRunsRemaining() async throws {
        var fired = 0
        let t = ToastTimer(duration: 0.2) { fired += 1 }
        t.start()
        try await Task.sleep(for: .milliseconds(50))
        t.pause()
        try await Task.sleep(for: .milliseconds(400)) // past 0.2 while paused
        XCTAssertEqual(fired, 0, "paused timer must not fire")
        t.resume()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(fired, 1, "resume fires the remaining time")
    }

    func testCancelPreventsFire() async throws {
        var fired = 0
        let t = ToastTimer(duration: 0.1) { fired += 1 }
        t.start()
        t.cancel()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(fired, 0)
    }
}
