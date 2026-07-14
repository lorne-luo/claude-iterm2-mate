import XCTest
@testable import ClaudeItermMate

final class ItermSessionLookupTests: XCTestCase {
    func testParseSessionIDsFromIt2JSON() {
        let json = """
        [
          {"id": "EDB6BBBA-1", "name": "one", "tty": "/dev/ttys002"},
          {"id": "3421FE8E-2", "name": "two", "tty": "/dev/ttys001"}
        ]
        """.data(using: .utf8)!
        XCTAssertEqual(ItermSessionLookup.parseSessionIDs(json), ["EDB6BBBA-1", "3421FE8E-2"])
    }

    func testParseSessionIDsToleratesGarbageAndEmpty() {
        XCTAssertTrue(ItermSessionLookup.parseSessionIDs(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(ItermSessionLookup.parseSessionIDs(Data("[]".utf8)).isEmpty)
        // Objects without an "id" contribute nothing.
        XCTAssertTrue(ItermSessionLookup.parseSessionIDs(Data("[{\"name\":\"x\"}]".utf8)).isEmpty)
    }

    func testUnavailableIt2MeansNotFindable() {
        let lookup = ItermSessionLookup(it2URL: nil)
        XCTAssertNil(lookup.liveSessionIDs())
        XCTAssertFalse(lookup.canFind("any-uuid"))
    }
}
