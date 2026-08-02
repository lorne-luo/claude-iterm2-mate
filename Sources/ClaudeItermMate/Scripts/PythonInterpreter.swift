import Foundation

/// Resolves a Python interpreter that can `import iterm2` — required by the two
/// bundled scripts (`iterm-focus-pane.py`, `set-pane-bg.py`).
///
/// The `it2` CLI is already a documented prerequisite (`uv tool install it2`) and
/// its launcher is itself a Python script whose shebang is the absolute path of
/// the venv interpreter that has `iterm2`. Reading that shebang therefore costs
/// nothing extra and makes no assumption about uv/pipx/venv directory layout.
///
/// Resolved at call time, never persisted: rewriting a script's shebang at
/// install time would freeze the path and silently break when the user
/// reinstalls `it2` onto a different Python.
enum PythonInterpreter {
    /// Pure, unit-tested shebang extractor.
    ///
    /// Returns nil for an *indirect* shebang (`#!/usr/bin/env python3`): that
    /// resolves to the system Python, which does NOT have `iterm2` (verified:
    /// `ModuleNotFoundError`), so using it would fail silently at spawn time.
    static func parseShebang(_ firstLine: String) -> String? {
        guard firstLine.hasPrefix("#!") else { return nil }
        let body = firstLine.dropFirst(2).trimmingCharacters(in: .whitespaces)
        // Interpreter is the first token; any remaining tokens are its args.
        guard let path = body.split(separator: " ", maxSplits: 1).first.map(String.init),
              path.hasPrefix("/"),
              URL(fileURLWithPath: path).lastPathComponent != "env"
        else { return nil }
        return path
    }

    /// Interpreter for the bundled scripts, or nil when `it2` is absent.
    static func resolve(it2URL: URL? = ItermFocusAction.resolveIt2()) -> URL? {
        guard let it2URL else { return nil }
        let fm = FileManager.default
        // `it2` may be a symlink (~/.local/bin/it2 -> the venv's bin/it2); the
        // shebang and the sibling fallback must both come from the real file.
        let real = URL(fileURLWithPath: (try? fm.destinationOfSymbolicLink(atPath: it2URL.path))
            .map { $0.hasPrefix("/") ? $0 : it2URL.deletingLastPathComponent().appendingPathComponent($0).path }
            ?? it2URL.path)

        if let head = firstLine(of: real),
           let path = parseShebang(head),
           fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let sibling = real.deletingLastPathComponent().appendingPathComponent("python")
        return fm.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    /// First line of a file, read without slurping the whole thing.
    private static func firstLine(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512), let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.split(separator: "\n", maxSplits: 1).first.map(String.init)
    }
}
