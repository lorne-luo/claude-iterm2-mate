import XCTest
@testable import ClaudeItermMate

final class QuickReplyTests: XCTestCase {
    /// The bar renders `QuickReply.all` verbatim, so the list is the contract:
    /// four prompts, stable ids, and no empty field (an empty symbol renders as a
    /// blank button, an empty text submits an empty line).
    func testAllIsTheFourCannedPrompts() {
        let all = QuickReply.all
        XCTAssertEqual(all.map(\.id), ["continue", "commit", "commit-push", "commit-push-pr"])
        for reply in all {
            XCTAssertFalse(reply.symbol.isEmpty)
            XCTAssertFalse(reply.label.isEmpty)
            XCTAssertFalse(reply.text.isEmpty)
        }
        XCTAssertEqual(Set(all.map(\.symbol)).count, all.count, "each prompt gets its own icon")
        // The label doubles as the tooltip and the hover caption, so a duplicate
        // would make two icons indistinguishable on hover.
        XCTAssertEqual(Set(all.map(\.label)).count, all.count, "each prompt gets its own caption")
    }

    func testTextsAreTheRequestedPrompts() {
        XCTAssertEqual(QuickReply.all.map(\.text), [
            "continue",
            "commit to git",
            "commit to git and push to remote",
            "commit to git and push to remote and create pr with description refined",
        ])
    }

    /// Text first, then the submit key — never one fragment: the composer must
    /// hold the whole line before it is submitted.
    func testSubmitSequenceIsTextThenCarriageReturn() {
        XCTAssertEqual(ItermSendTextAction.submitSequence(text: "commit to git"),
                       ["commit to git", "\r"])
        XCTAssertEqual(ItermSendTextAction.submitSequence(text: "continue").last, "\r")
    }

    /// `\r`, not `\n` — Claude Code's raw-mode TUI submits on carriage return.
    func testSubmitKeyIsCarriageReturn() {
        XCTAssertEqual(ItermSendTextAction.submit, "\r")
    }

    func testArgumentsCarryTheSessionAndFragment() {
        XCTAssertEqual(
            ItermSendTextAction.arguments(sessionUUID: "S1", fragment: "commit to git"),
            ["session", "send", "-s", "S1", "commit to git"]
        )
    }
}
