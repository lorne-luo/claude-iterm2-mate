import Foundation

/// Worktree shade level for a pane background. A pane background has no glyph to
/// tell same-repo worktrees apart (they share one color slot), so siblings are
/// separated by a darkness step instead: mainline (main/master/none) is the
/// darkest base (level 0); each linked worktree gets a deterministic non-zero
/// level from its branch name. Dark-space discriminability is limited, so the
/// level count is small and collisions degrade gracefully. Pure and testable.
enum PaneShade {
    /// Number of shade levels (0 = mainline base, 1...levels-1 = worktrees).
    static let levels = 3

    static func level(branch: String?, isWorktree: Bool) -> Int {
        guard isWorktree else { return 0 }
        // A mainline / unnamed branch renders the default glyph — keep it darkest.
        guard ReminderIdentity.glyph(for: branch) != ReminderIdentity.defaultGlyph else { return 0 }
        let b = branch ?? ""
        return 1 + Int(ReminderIdentity.stableHash(b) % UInt64(levels - 1))
    }
}
