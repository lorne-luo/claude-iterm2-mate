import XCTest
@testable import ClaudeItermMate

final class ItermColorActionTests: XCTestCase {
    func testStashArgumentsCarryOnlyTheStashKey() {
        XCTAssertEqual(
            ItermColorAction.stashArguments(sessionUUID: "ABC-123"),
            ["session", "send", "-s", "ABC-123", "\u{13}"]
        )
    }

    func testArgumentsBuildSlashCommandWithCRSubmit() {
        let args = ItermColorAction.arguments(sessionUUID: "ABC-123", colorName: "red")
        // \r (not \n): Claude Code's TUI only submits on carriage return.
        XCTAssertEqual(args, ["session", "send", "-s", "ABC-123", "/color red\r"])
    }

    func testCommandSendNeverCarriesTheStashKey() {
        // The stash is its own send; smuggling it back into the command send
        // would reintroduce the race this split exists to remove.
        for name in ReminderPalette.names {
            let text = ItermColorAction.arguments(sessionUUID: "S", colorName: name).last!
            XCTAssertFalse(text.contains(ItermColorAction.stashKey))
            XCTAssertEqual(text, "/color \(name)\r")
            XCTAssertLessThan(text.utf8.count, 32, "injected text must stay tiny")
        }
    }

    func testUnavailableIt2IsReported() {
        XCTAssertFalse(ItermColorAction(it2URL: nil).available)
        XCTAssertTrue(ItermColorAction(it2URL: URL(fileURLWithPath: "/usr/bin/true")).available)
    }
}
