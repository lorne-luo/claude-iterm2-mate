import XCTest
@testable import ClaudeItermMate

final class UvLocatorTests: XCTestCase {
    /// A GUI-launched app inherits only launchd's PATH, so `uv` must be looked
    /// for at absolute locations — never by name. Same three roots, same order,
    /// as `ItermFocusAction`'s `it2` lookup.
    func testCandidatesAreAbsolutePathsInPreferenceOrder() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(
            UvLocator.candidates.map(\.path),
            ["\(home)/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
        )
    }

    func testCandidatesCarryNoRelativeComponents() {
        for candidate in UvLocator.candidates {
            XCTAssertTrue(candidate.path.hasPrefix("/"), candidate.path)
            XCTAssertFalse(candidate.path.contains(".."), candidate.path)
        }
    }
}
