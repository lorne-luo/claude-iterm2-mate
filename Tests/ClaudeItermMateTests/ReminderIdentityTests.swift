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

    func testIsMainLine() {
        XCTAssertTrue(ReminderIdentity(repoRoot: nil, branch: "main", cwd: "/x").isMainLine)
        XCTAssertTrue(ReminderIdentity(repoRoot: nil, branch: "master", cwd: "/x").isMainLine)
        XCTAssertTrue(ReminderIdentity(repoRoot: nil, branch: nil, cwd: "/x").isMainLine)
        XCTAssertFalse(ReminderIdentity(repoRoot: nil, branch: "feature/auth", cwd: "/x").isMainLine)
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

    // MARK: location label (branch name vs worktree path)

    func testLocationLabelIsBranchForNormalCheckout() {
        XCTAssertEqual(
            ReminderIdentity.locationLabel(repoRoot: "/x/proj", cwd: "/x/proj", branch: "main", isWorktree: false),
            "main"
        )
        XCTAssertEqual(
            ReminderIdentity.locationLabel(repoRoot: "/x/proj", cwd: "/x/proj/sub", branch: "feat/a", isWorktree: false),
            "feat/a"
        )
    }

    func testLocationLabelIsRelativePathForWorktreeUnderRepo() {
        // .worktree/feat is far shorter than the absolute path → relative wins.
        XCTAssertEqual(
            ReminderIdentity.locationLabel(
                repoRoot: "/Users/me/proj", cwd: "/Users/me/proj/.worktree/feat",
                branch: "feat", isWorktree: true
            ),
            ".worktree/feat"
        )
    }

    func testLocationLabelIsAbsoluteWhenShorterThanRelative() {
        // Worktree far from the repo: the `..`-heavy relative path is longer
        // than the absolute, so the absolute path is shown.
        let repoRoot = "/Users/me/deeply/nested/project/root"
        let cwd = "/tmp/wt"
        XCTAssertEqual(
            ReminderIdentity.locationLabel(repoRoot: repoRoot, cwd: cwd, branch: "feat", isWorktree: true),
            cwd
        )
    }

    func testLocationLabelFallsBackToCwdWithoutRepoRoot() {
        XCTAssertEqual(
            ReminderIdentity.locationLabel(repoRoot: nil, cwd: "/tmp/wt", branch: "feat", isWorktree: true),
            "/tmp/wt"
        )
    }

    func testRelativePathComputesDotDotSegments() {
        XCTAssertEqual(ReminderIdentity.relativePath(from: "/a/b/c", to: "/a/b/c/d/e"), "d/e")
        XCTAssertEqual(ReminderIdentity.relativePath(from: "/a/b/c", to: "/a/x"), "../../x")
        XCTAssertEqual(ReminderIdentity.relativePath(from: "/a/b", to: "/a/b"), ".")
    }
}
