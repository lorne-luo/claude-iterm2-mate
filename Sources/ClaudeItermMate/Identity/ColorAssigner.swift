import Foundation

/// In-memory color authority shared by the session-start injection path and
/// the tab renderer. Assigns each project (repo root / cwd) one of the 8
/// `/color` palette slots, and each linked worktree of a repo a lighten level,
/// so the Claude Code prompt bar and the app's tab show the same color name.
///
/// Deterministic first, collision-averse second: a repo's preferred slot is
/// its FNV-1a hash mod 8 (same derivation as `ReminderIdentity`), but if that
/// slot is already held by a DIFFERENT live repo, linear-probe to the next
/// free one. With more than 8 live repos slots must repeat; the preferred
/// slot is reused then. Assignments are stable for the app's lifetime.
/// Pure, synchronous, timer-free — fully unit-testable.
final class ColorAssigner {
    private var slotByRepo: [String: Int] = [:]
    /// First-seen order of worktree branches per repo; index+1 = lighten level.
    private var worktreeBranchesByRepo: [String: [String]] = [:]

    /// The palette slot for a project key (stable across calls).
    func colorIndex(for key: String) -> Int {
        if let existing = slotByRepo[key] { return existing }
        let n = ReminderIdentity.paletteCount
        let preferred = Int(ReminderIdentity.stableHash(key) % UInt64(n))
        let taken = Set(slotByRepo.values)
        var slot = preferred
        if taken.count < n {
            while taken.contains(slot) { slot = (slot + 1) % n }
        }
        slotByRepo[key] = slot
        return slot
    }

    /// The `/color` name injected into sessions of this project.
    func colorName(for key: String) -> String {
        ReminderPalette.colorName(at: colorIndex(for: key))
    }

    /// Lighten level for a session: 0 for the main working tree; linked
    /// worktrees get 1, 2, ... in first-seen branch order (same branch keeps
    /// its level). Falls back to `cwd` as the branch key when branch is nil.
    func lightenLevel(for key: String, branch: String?, isWorktree: Bool, cwd: String) -> Int {
        guard isWorktree else { return 0 }
        let branchKey = branch ?? cwd
        var branches = worktreeBranchesByRepo[key] ?? []
        if let i = branches.firstIndex(of: branchKey) { return i + 1 }
        branches.append(branchKey)
        worktreeBranchesByRepo[key] = branches
        return branches.count
    }
}
