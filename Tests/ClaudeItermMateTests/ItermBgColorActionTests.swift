import XCTest
@testable import ClaudeItermMate

final class ItermBgColorActionTests: XCTestCase {
    func testArgumentsAreSessionThenHex() {
        XCTAssertEqual(
            ItermBgColorAction.arguments(sessionUUID: "ABC-123", hex: "2E4057"),
            ["ABC-123", "2E4057"]
        )
    }

    func testAvailabilityFollowsScriptExecutability() {
        XCTAssertFalse(
            ItermBgColorAction(scriptURL: URL(fileURLWithPath: "/no/such/set-pane-bg.py")).available
        )
        XCTAssertTrue(
            ItermBgColorAction(scriptURL: URL(fileURLWithPath: "/usr/bin/true")).available
        )
    }
}
