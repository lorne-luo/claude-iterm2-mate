import XCTest
@testable import ClaudeItermMate

final class ItermFocusActionTests: XCTestCase {
    func testDefaultScriptURLIsExpandedAbsolutePath() {
        let path = ItermFocusAction.defaultScriptURL.path
        XCTAssertFalse(path.contains("~"), "Process does not expand ~; path must be absolute")
        XCTAssertTrue(path.hasSuffix(".claude/scripts/iterm-focus-pane.py"))
        XCTAssertTrue(path.hasPrefix("/"))
    }

    func testIsAvailableFalseForMissingScript() {
        let action = ItermFocusAction(scriptURL: URL(fileURLWithPath: "/nonexistent/script.py"))
        XCTAssertFalse(action.isAvailable)
    }

    func testProcessBuilderPassesUUIDAsArgument() {
        let url = URL(fileURLWithPath: "/some/script.py")
        let p = ItermFocusAction.launch(processFor: url, sessionUUID: "ABC-123")
        XCTAssertEqual(p.executableURL, url)
        XCTAssertEqual(p.arguments, ["ABC-123"])
    }

    func testFocusWithMissingScriptDoesNotThrowOrBlock() {
        let action = ItermFocusAction(scriptURL: URL(fileURLWithPath: "/nonexistent/script.py"))
        action.focus(sessionUUID: "ABC-123") // must be a silent no-op
    }
}
