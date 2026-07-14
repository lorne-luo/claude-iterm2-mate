import XCTest
@testable import ClaudeItermMate

final class ItermColorActionTests: XCTestCase {
    func testArgumentsBuildStashedSlashCommandWithCRSubmit() {
        let args = ItermColorAction.arguments(sessionUUID: "ABC-123", colorName: "red")
        // \r (not \n): Claude Code's TUI only submits on carriage return.
        XCTAssertEqual(args, ["session", "send", "-s", "ABC-123", "\u{13}/color red\r"])
    }

    func testInjectedTextStartsWithStashKeyAndStaysTiny() {
        for name in ReminderPalette.names {
            let text = ItermColorAction.arguments(sessionUUID: "S", colorName: name).last!
            XCTAssertTrue(text.hasPrefix(ItermColorAction.stashKey))
            XCTAssertEqual(text, "\u{13}/color \(name)\r")
            XCTAssertLessThan(text.utf8.count, 32, "injected text must stay tiny")
        }
    }

    func testUnavailableIt2IsReported() {
        XCTAssertFalse(ItermColorAction(it2URL: nil).available)
        XCTAssertTrue(ItermColorAction(it2URL: URL(fileURLWithPath: "/usr/bin/true")).available)
    }
}
