import XCTest
@testable import ClaudeItermMate

final class ItermFocusActionTests: XCTestCase {
    func testDefaultScriptURLIsExpandedAbsolutePath() {
        let path = ItermFocusAction.defaultScriptURL.path
        XCTAssertFalse(path.contains("~"), "Process does not expand ~; path must be absolute")
        XCTAssertTrue(path.hasSuffix(".claude/scripts/iterm-focus-pane.py"))
        XCTAssertTrue(path.hasPrefix("/"))
    }

    func testScriptAvailableFalseForMissingScript() {
        let action = ItermFocusAction(scriptURL: URL(fileURLWithPath: "/nonexistent/script.py"), it2URL: nil)
        XCTAssertFalse(action.scriptAvailable)
        XCTAssertFalse(action.it2Available)
        XCTAssertFalse(action.canFocus)
    }

    func testCanFocusWhenOnlyIt2Available() {
        let action = ItermFocusAction(
            scriptURL: URL(fileURLWithPath: "/nonexistent/script.py"),
            it2URL: URL(fileURLWithPath: "/some/it2")
        )
        XCTAssertTrue(action.canFocus)
    }

    func testScriptProcessBuilderPassesUUIDAsArgument() {
        let url = URL(fileURLWithPath: "/some/script.py")
        let p = ItermFocusAction.launch(processFor: url, sessionUUID: "ABC-123")
        XCTAssertEqual(p.executableURL, url)
        XCTAssertEqual(p.arguments, ["ABC-123"])
    }

    func testIt2ProcessBuilderPassesArguments() {
        let url = URL(fileURLWithPath: "/some/it2")
        let p = ItermFocusAction.it2Process(it2URL: url, arguments: ["session", "focus", "ABC-123"])
        XCTAssertEqual(p.executableURL, url)
        XCTAssertEqual(p.arguments, ["session", "focus", "ABC-123"])
    }

    func testPlanPrefersScriptWhenMaximizingAndScriptPresent() {
        XCTAssertEqual(
            ItermFocusAction.plan(maximize: true, scriptAvailable: true, it2Available: true),
            .script
        )
    }

    func testPlanUsesIt2WhenMaximizeOff() {
        XCTAssertEqual(
            ItermFocusAction.plan(maximize: false, scriptAvailable: true, it2Available: true),
            .it2FocusOnly
        )
    }

    func testPlanFallsBackToScriptWhenMaximizeOffButNoIt2() {
        XCTAssertEqual(
            ItermFocusAction.plan(maximize: false, scriptAvailable: true, it2Available: false),
            .script
        )
    }

    func testPlanFallsBackToIt2WhenMaximizeOnButNoScript() {
        XCTAssertEqual(
            ItermFocusAction.plan(maximize: true, scriptAvailable: false, it2Available: true),
            .it2FocusOnly
        )
    }

    func testPlanUnavailableWhenNothingPresent() {
        XCTAssertEqual(
            ItermFocusAction.plan(maximize: true, scriptAvailable: false, it2Available: false),
            .unavailable
        )
    }

    func testFocusWithNothingAvailableDoesNotThrowOrBlock() {
        let action = ItermFocusAction(scriptURL: URL(fileURLWithPath: "/nonexistent/script.py"), it2URL: nil)
        action.focus(sessionUUID: "ABC-123", maximize: true) // silent no-op
    }
}
