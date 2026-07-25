import XCTest
@testable import ClaudeItermMate

final class ItermSessionLookupTests: XCTestCase {
    func testParseSessionIDsFromAppleScriptList() {
        let out = Data("EDB6BBBA-1, 3421FE8E-2, DC30D8BD-3\n".utf8)
        XCTAssertEqual(ItermSessionLookup.parseSessionIDs(out), ["EDB6BBBA-1", "3421FE8E-2", "DC30D8BD-3"])
    }

    func testParseSessionIDsToleratesEmptyOutput() {
        // iTerm2 not running: the `is running` guard yields no output.
        XCTAssertTrue(ItermSessionLookup.parseSessionIDs(Data()).isEmpty)
        XCTAssertTrue(ItermSessionLookup.parseSessionIDs(Data("\n".utf8)).isEmpty)
    }

    func testParseSessionIDsHandlesSingleSessionWithoutSeparator() {
        XCTAssertEqual(ItermSessionLookup.parseSessionIDs(Data("A5E8F096-1\n".utf8)), ["A5E8F096-1"])
    }

    func testMissingOsascriptMeansNotFindable() {
        let lookup = ItermSessionLookup(osascriptURL: URL(fileURLWithPath: "/nonexistent/osascript"))
        XCTAssertNil(lookup.liveSessionIDs())
        XCTAssertFalse(lookup.canFind("any-uuid"))
    }
}
