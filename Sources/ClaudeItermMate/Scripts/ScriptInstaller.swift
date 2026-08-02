import Foundation

/// Publishes the bundled iTerm2 Python API scripts to App Support.
///
/// Deliberately independent of `HookInstaller`: these scripts back pane coloring
/// and click-to-jump, which are orthogonal to whether the user opted into the
/// Claude Code hooks. Hanging them off the hook installer would leave a
/// hook-less user without them. This writes only inside our own App Support
/// directory — never `~/.claude/`.
struct ScriptInstaller {
    enum InstallError: Error {
        case bundledScriptMissing(String)
    }

    /// Basenames (without extension) of the bundled `.py` scripts.
    static let scriptNames = ["iterm-focus-pane", "set-pane-bg"]

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeItermMate")
    }

    static func destURL(for name: String) -> URL {
        supportDirectory.appendingPathComponent("\(name).py")
    }

    /// Idempotent; re-run on every launch so a new app version's scripts
    /// propagate. Publishes atomically (temp + swap) — a plain remove-then-copy
    /// leaves a window where an in-flight reminder would spawn a missing file.
    func install() throws {
        let fm = FileManager.default
        for name in Self.scriptNames {
            guard let bundled = Bundle.module.url(forResource: name, withExtension: "py") else {
                throw InstallError.bundledScriptMissing(name)
            }
            let dest = Self.destURL(for: name)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = dest.appendingPathExtension("tmp-\(UUID().uuidString)")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: bundled, to: tmp)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        }
    }
}
