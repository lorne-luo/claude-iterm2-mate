import XCTest
@testable import ClaudeItermMate

final class ItermSendTextActionTests: XCTestCase {
    typealias Answer = ItermSendTextAction.Answer

    func testSingleSelectSendsJustTheDigit() {
        XCTAssertEqual(ItermSendTextAction.injectionSequence(.option(3), optionCount: 4), ["3"])
    }

    func testFreeTextNavigatesToTypeRowThenTypesThenSubmits() {
        // K = 3 options → "Type something" is row 4.
        XCTAssertEqual(
            ItermSendTextAction.injectionSequence(.text("watermelon"), optionCount: 3),
            ["4", "watermelon", "\r"]
        )
    }

    func testMultiSelectTogglesThenRightArrowThenSubmit() {
        XCTAssertEqual(
            ItermSendTextAction.injectionSequence(.multi([1, 3]), optionCount: 3),
            ["1", "3", "\u{1b}[C", "1"]
        )
    }

    func testMultiSelectEmptyStillGoesToSubmitPage() {
        XCTAssertEqual(
            ItermSendTextAction.injectionSequence(.multi([]), optionCount: 3),
            ["\u{1b}[C", "1"]
        )
    }

    func testArgumentsBuildsIt2SessionSend() {
        XCTAssertEqual(
            ItermSendTextAction.arguments(sessionUUID: "S1", fragment: "2"),
            ["session", "send", "-s", "S1", "2"]
        )
    }
}
