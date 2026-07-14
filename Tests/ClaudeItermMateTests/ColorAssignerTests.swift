import XCTest
@testable import ClaudeItermMate

final class ColorAssignerTests: XCTestCase {
    private func preferredIndex(_ key: String) -> Int {
        Int(ReminderIdentity.stableHash(key) % UInt64(ReminderIdentity.paletteCount))
    }

    func testAssignmentIsStableAcrossCalls() {
        let a = ColorAssigner()
        let first = a.colorIndex(for: "/x/proj")
        XCTAssertEqual(a.colorIndex(for: "/x/proj"), first)
        XCTAssertEqual(a.colorIndex(for: "/x/proj"), first)
    }

    func testFirstRepoGetsItsPreferredHashSlot() {
        let a = ColorAssigner()
        XCTAssertEqual(a.colorIndex(for: "/x/proj"), preferredIndex("/x/proj"))
    }

    func testCollidingRepoProbesToNextFreeSlot() {
        // Find two keys whose preferred slots collide.
        let base = "/x/proj"
        let want = preferredIndex(base)
        var other = ""
        for i in 0..<10_000 {
            let candidate = "/y/repo\(i)"
            if preferredIndex(candidate) == want, candidate != base {
                other = candidate
                break
            }
        }
        XCTAssertFalse(other.isEmpty, "no colliding key found")

        let a = ColorAssigner()
        let first = a.colorIndex(for: base)
        let second = a.colorIndex(for: other)
        XCTAssertNotEqual(first, second, "live repos must not share a slot while free ones remain")
        XCTAssertEqual(second, (want + 1) % ReminderIdentity.paletteCount)
    }

    func testEightDistinctReposFillAllSlotsWithoutRepeats() {
        let a = ColorAssigner()
        var used = Set<Int>()
        for i in 0..<ReminderIdentity.paletteCount {
            used.insert(a.colorIndex(for: "/repo/\(i)"))
        }
        XCTAssertEqual(used.count, ReminderIdentity.paletteCount)
    }

    func testNinthRepoFallsBackToPreferredSlot() {
        let a = ColorAssigner()
        for i in 0..<ReminderIdentity.paletteCount {
            _ = a.colorIndex(for: "/repo/\(i)")
        }
        let ninth = "/repo/overflow"
        XCTAssertEqual(a.colorIndex(for: ninth), preferredIndex(ninth))
    }

    func testColorNameMatchesPaletteSlot() {
        let a = ColorAssigner()
        let idx = a.colorIndex(for: "/x/proj")
        XCTAssertEqual(a.colorName(for: "/x/proj"), ReminderPalette.names[idx])
    }

    func testMainWorkingTreeIsLevelZero() {
        let a = ColorAssigner()
        XCTAssertEqual(a.lightenLevel(for: "/x/proj", branch: "main", isWorktree: false, cwd: "/x/proj"), 0)
        XCTAssertEqual(a.lightenLevel(for: "/x/proj", branch: "feat/a", isWorktree: false, cwd: "/x/proj"), 0)
    }

    func testWorktreesGetIncreasingLevelsAndKeepThem() {
        let a = ColorAssigner()
        let key = "/x/proj"
        XCTAssertEqual(a.lightenLevel(for: key, branch: "feat/a", isWorktree: true, cwd: "/wt/a"), 1)
        XCTAssertEqual(a.lightenLevel(for: key, branch: "feat/b", isWorktree: true, cwd: "/wt/b"), 2)
        // Same branch keeps its level; a different repo starts from 1 again.
        XCTAssertEqual(a.lightenLevel(for: key, branch: "feat/a", isWorktree: true, cwd: "/wt/a"), 1)
        XCTAssertEqual(a.lightenLevel(for: "/other", branch: "feat/a", isWorktree: true, cwd: "/wt/o"), 1)
    }

    func testWorktreeWithoutBranchFallsBackToCwd() {
        let a = ColorAssigner()
        let key = "/x/proj"
        XCTAssertEqual(a.lightenLevel(for: key, branch: nil, isWorktree: true, cwd: "/wt/a"), 1)
        XCTAssertEqual(a.lightenLevel(for: key, branch: nil, isWorktree: true, cwd: "/wt/a"), 1)
        XCTAssertEqual(a.lightenLevel(for: key, branch: nil, isWorktree: true, cwd: "/wt/b"), 2)
    }
}
