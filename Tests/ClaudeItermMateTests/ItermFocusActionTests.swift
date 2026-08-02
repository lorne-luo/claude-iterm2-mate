import XCTest
@testable import ClaudeItermMate

final class ItermFocusActionTests: XCTestCase {
    func testDefaultScriptURLIsExpandedAbsolutePath() {
        let path = ItermFocusAction.defaultScriptURL.path
        XCTAssertFalse(path.contains("~"), "Process does not expand ~; path must be absolute")
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/ClaudeItermMate/iterm-focus-pane.py"))
        XCTAssertTrue(path.hasPrefix("/"))
    }

    func testScriptAvailableFalseForMissingScript() {
        let action = ItermFocusAction(scriptURL: URL(fileURLWithPath: "/nonexistent/script.py"), it2URL: nil)
        XCTAssertFalse(action.scriptAvailable)
        XCTAssertFalse(action.it2Available)
        XCTAssertFalse(action.canFocus)
    }

    /// The script needs the it2 venv's Python; a present script with no
    /// interpreter cannot run, so it must not count as available. The explicit
    /// init must honour `interpreter: nil` — a defaulted parameter would have
    /// silently fallen back to resolving the real machine's interpreter.
    func testScriptUnavailableWithoutInterpreter() {
        let action = ItermFocusAction(
            scriptURL: URL(fileURLWithPath: "/usr/bin/true"),
            it2URL: ItermFocusAction.resolveIt2(),
            interpreter: nil
        )
        XCTAssertFalse(action.scriptAvailable)
    }

    func testScriptAvailableWithInterpreterAndScript() {
        let action = ItermFocusAction(
            scriptURL: URL(fileURLWithPath: "/usr/bin/true"),
            it2URL: nil,
            interpreter: URL(fileURLWithPath: "/usr/bin/true")
        )
        XCTAssertTrue(action.scriptAvailable)
    }

    func testCanFocusWhenOnlyIt2Available() {
        let action = ItermFocusAction(
            scriptURL: URL(fileURLWithPath: "/nonexistent/script.py"),
            it2URL: URL(fileURLWithPath: "/some/it2")
        )
        XCTAssertTrue(action.canFocus)
    }

    func testScriptProcessBuilderRunsScriptThroughInterpreter() {
        let interpreter = URL(fileURLWithPath: "/opt/venv/bin/python")
        let p = ItermFocusAction.launch(
            interpreter: interpreter, scriptPath: "/some/script.py", sessionUUID: "ABC-123"
        )
        XCTAssertEqual(p.executableURL, interpreter)
        XCTAssertEqual(p.arguments, ["/some/script.py", "ABC-123"])
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
