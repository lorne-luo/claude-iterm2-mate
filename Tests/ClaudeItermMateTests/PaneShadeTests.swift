import XCTest
@testable import ClaudeItermMate

final class PaneShadeTests: XCTestCase {
    func testNonWorktreeIsAlwaysBase() {
        XCTAssertEqual(PaneShade.level(branch: "feature/x", isWorktree: false), 0)
        XCTAssertEqual(PaneShade.level(branch: nil, isWorktree: false), 0)
    }

    func testMainlineAndUnnamedAreBase() {
        for b in ["main", "master", "MAIN", nil, ""] {
            XCTAssertEqual(PaneShade.level(branch: b, isWorktree: true), 0,
                           "\(b ?? "nil"): mainline/unnamed must be the darkest base")
        }
    }

    func testWorktreeBranchGetsNonZeroLevel() {
        for b in ["feature/a", "fix-bug", "release/2.0"] {
            let level = PaneShade.level(branch: b, isWorktree: true)
            XCTAssertGreaterThanOrEqual(level, 1, "\(b): worktree must not be base")
            XCTAssertLessThan(level, PaneShade.levels, "\(b): level within range")
        }
    }

    func testDeterministic() {
        XCTAssertEqual(
            PaneShade.level(branch: "feature/a", isWorktree: true),
            PaneShade.level(branch: "feature/a", isWorktree: true)
        )
    }
}
