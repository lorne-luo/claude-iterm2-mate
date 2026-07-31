import XCTest
@testable import ClaudeItermMate

final class ItermBgColorActionTests: XCTestCase {
    func testArgumentsAreSessionThenHex() {
        XCTAssertEqual(
            ItermBgColorAction.arguments(sessionUUID: "ABC-123", hex: "2E4057"),
            ["ABC-123", "2E4057"]
        )
    }

    func testInterpreterArgumentsPutScriptPathFirst() {
        XCTAssertEqual(
            ItermBgColorAction.arguments(
                scriptPath: "/support/set-pane-bg.py", sessionUUID: "ABC-123", hex: "2E4057"
            ),
            ["/support/set-pane-bg.py", "ABC-123", "2E4057"]
        )
    }

    /// Availability needs BOTH halves: the script file and a Python that has
    /// `iterm2` (the it2 venv's). Either one alone cannot color a pane.
    func testAvailabilityNeedsScriptAndInterpreter() {
        let python = URL(fileURLWithPath: "/usr/bin/true")
        XCTAssertFalse(
            ItermBgColorAction(
                scriptURL: URL(fileURLWithPath: "/no/such/set-pane-bg.py"), interpreter: python
            ).available
        )
        XCTAssertFalse(
            ItermBgColorAction(
                scriptURL: URL(fileURLWithPath: "/usr/bin/true"), interpreter: nil
            ).available
        )
        XCTAssertTrue(
            ItermBgColorAction(
                scriptURL: URL(fileURLWithPath: "/usr/bin/true"), interpreter: python
            ).available
        )
    }
}
