import Foundation

/// In-memory color authority shared by the session-start injection path and
/// the tab renderer. Assigns each project (repo root / cwd) one of the 8
/// `/color` palette slots so the Claude Code prompt bar and the app's tab show
/// the same color name. (Tab lighten levels for concurrent same-directory
/// sessions are owned by `ReminderStore`, not here.)
///
/// Deterministic first, collision-averse second: a repo's preferred slot is
/// its FNV-1a hash mod 8 (same derivation as `ReminderIdentity`), but if that
/// slot is already held by a DIFFERENT live repo, linear-probe to the next
/// free one. With more than 8 live repos slots must repeat; the preferred
/// slot is reused then. Assignments are stable for the app's lifetime.
/// Pure, synchronous, timer-free — fully unit-testable.
final class ColorAssigner {
    private var slotByRepo: [String: Int] = [:]

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
}
