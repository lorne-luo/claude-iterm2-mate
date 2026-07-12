import XCTest
@testable import ClaudeItermMate

final class ReminderIdentityTests: XCTestCase {
    // MARK: project

    func testProjectUsesRepoRootBasename() {
        let id = ReminderIdentity(repoRoot: "/Users/me/Workspace/myproj", branch: nil, cwd: "/Users/me/Workspace/myproj/sub/dir")
        XCTAssertEqual(id.project, "myproj")
    }

    func testProjectFallsBackToCwdWhenRepoRootNil() {
        let id = ReminderIdentity(repoRoot: nil, branch: nil, cwd: "/Users/me/Workspace/other")
        XCTAssertEqual(id.project, "other")
    }

    func testProjectFallsBackToCwdWhenRepoRootEmpty() {
        let id = ReminderIdentity(repoRoot: "", branch: nil, cwd: "/Users/me/Workspace/other")
        XCTAssertEqual(id.project, "other")
    }

    // MARK: worktreeGlyph

    func testGlyphIsFirstCharOfLastBranchSegmentUppercased() {
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: "feature/auth-refactor", cwd: "/x").worktreeGlyph, "A")
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: "hotfix", cwd: "/x").worktreeGlyph, "H")
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: "release/v1.2", cwd: "/x").worktreeGlyph, "V")
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: "a/b/c-thing", cwd: "/x").worktreeGlyph, "C")
    }

    func testGlyphForMainAndMasterIsDot() {
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: "main", cwd: "/x").worktreeGlyph, "●")
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: "master", cwd: "/x").worktreeGlyph, "●")
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: "MAIN", cwd: "/x").worktreeGlyph, "●")
    }

    func testGlyphForNilOrEmptyBranchIsDot() {
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: nil, cwd: "/x").worktreeGlyph, "●")
        XCTAssertEqual(ReminderIdentity(repoRoot: nil, branch: "", cwd: "/x").worktreeGlyph, "●")
    }

    // MARK: colorIndex

    func testColorIndexIsStableAcrossInstances() {
        let a = ReminderIdentity(repoRoot: "/Users/me/proj", branch: "main", cwd: "/x")
        let b = ReminderIdentity(repoRoot: "/Users/me/proj", branch: "feature/z", cwd: "/y")
        XCTAssertEqual(a.colorIndex, b.colorIndex, "colorIndex must depend only on repoRoot, not branch/cwd")
    }

    func testColorIndexUsesCwdWhenRepoRootNil() {
        let a = ReminderIdentity(repoRoot: nil, branch: nil, cwd: "/Users/me/proj")
        let b = ReminderIdentity(repoRoot: "/Users/me/proj", branch: nil, cwd: "/somewhere/else")
        XCTAssertEqual(a.colorIndex, b.colorIndex, "nil repoRoot must hash the same string as an equal repoRoot")
    }

    func testColorIndexAlwaysInPaletteRange() {
        for i in 0..<500 {
            let idx = ReminderIdentity(repoRoot: "/repo/path/\(i)-name", branch: nil, cwd: "/x").colorIndex
            XCTAssertGreaterThanOrEqual(idx, 0)
            XCTAssertLessThan(idx, ReminderIdentity.paletteCount)
        }
    }

    func testPaletteHasExactlyPaletteCountColors() {
        XCTAssertEqual(ReminderPalette.colors.count, ReminderIdentity.paletteCount)
    }

    // MARK: toast title

    func testToastTitleIncludesBranchWhenItFits() {
        XCTAssertEqual(ToastView.title(project: "myproj", branch: "main"), "[CC] myproj · main")
    }

    func testToastTitleOmitsBranchWhenNil() {
        XCTAssertEqual(ToastView.title(project: "myproj", branch: nil), "[CC] myproj")
    }

    func testToastTitleTruncatesOverlongBranch() {
        let title = ToastView.title(project: "myproj", branch: "feature/an-extremely-long-branch-name-that-overflows-the-toast-width")
        XCTAssertLessThanOrEqual(title.count, ToastView.titleBudget)
        XCTAssertTrue(title.hasPrefix("[CC] myproj · "), "project part must be preserved")
    }
}
