import XCTest
@testable import ClaudeItermMate

final class SmokeTests: XCTestCase {
    func testTargetLinks() {
        XCTAssertNotNil(AppDelegate())
    }
}
