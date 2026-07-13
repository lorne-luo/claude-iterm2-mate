import XCTest
@testable import ClaudeItermMate

@MainActor
final class SmokeTests: XCTestCase {
    func testTargetLinks() {
        XCTAssertNotNil(AppDelegate())
    }
}
