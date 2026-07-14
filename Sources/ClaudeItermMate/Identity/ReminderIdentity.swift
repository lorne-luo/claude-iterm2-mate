import Foundation

/// Derives a reminder's display identity — project label, worktree/branch glyph,
/// and palette color index — from its git/cwd context. Pure and deterministic:
/// the same input always yields the same values across process runs, unlike
/// `String.hashValue` which is per-process seeded.
struct ReminderIdentity: Equatable {
    /// Number of colors in `ReminderPalette`; `colorIndex` is taken mod this.
    static let paletteCount = 8
    static let defaultGlyph = "●"

    /// Full base path (`repoRoot` if present, else `cwd`). Uniquely identifies a
    /// project for dedup — unlike `project` (a basename), which can collide
    /// across unrelated repos that share a folder name.
    let key: String
    let project: String
    let worktreeGlyph: String
    let colorIndex: Int

    /// True for the main working tree (branch main/master, or no branch). The
    /// tab renders these with a "home" icon instead of a letter glyph.
    var isMainLine: Bool { worktreeGlyph == Self.defaultGlyph }

    init(repoRoot: String?, branch: String?, cwd: String) {
        let base = ReminderIdentity.nonEmpty(repoRoot) ?? cwd
        key = base
        project = (base as NSString).lastPathComponent
        worktreeGlyph = ReminderIdentity.glyph(for: branch)
        colorIndex = Int(ReminderIdentity.stableHash(base) % UInt64(ReminderIdentity.paletteCount))
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// The label shown where a branch name would go. For a normal checkout it
    /// is the branch name; for a linked worktree it is the worktree's location
    /// — whichever of the repo-relative or absolute path is shorter (so a
    /// worktree kept under the repo reads as e.g. `.worktree/feat`, while one
    /// elsewhere falls back to its absolute path).
    static func locationLabel(repoRoot: String?, cwd: String, branch: String?, isWorktree: Bool) -> String? {
        guard isWorktree else { return nonEmpty(branch) }
        guard let repoRoot = nonEmpty(repoRoot) else { return cwd }
        let rel = relativePath(from: repoRoot, to: cwd)
        return rel.count <= cwd.count ? rel : cwd
    }

    /// POSIX relative path from `base` to `target` using `..` where needed.
    static func relativePath(from base: String, to target: String) -> String {
        let b = base.split(separator: "/").map(String.init)
        let t = target.split(separator: "/").map(String.init)
        var i = 0
        while i < b.count, i < t.count, b[i] == t[i] { i += 1 }
        let parts = Array(repeating: "..", count: b.count - i) + Array(t[i...])
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    static func glyph(for branch: String?) -> String {
        guard let branch = nonEmpty(branch) else { return defaultGlyph }
        let lower = branch.lowercased()
        if lower == "main" || lower == "master" { return defaultGlyph }
        guard let segment = branch.split(separator: "/").last, let first = segment.first else {
            return defaultGlyph
        }
        return String(first).uppercased()
    }

    /// FNV-1a 64-bit over UTF-8 bytes — deterministic across process runs.
    static func stableHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}
