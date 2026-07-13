import Foundation

/// Whether the `mate-notify` Stop hook is installed and its script is on disk.
enum HookStatus: Equatable {
    case installed
    case notInstalled

    /// Decide status from a parsed settings.json dict.
    ///
    /// Scans every `Stop` hook group's `hooks[].command`, splits each command on
    /// whitespace, and looks for a token ending in `mate-notify.js`. The hook is
    /// `.installed` only when such a token exists AND `fileExists` reports the
    /// referenced path present. `fileExists` is injected so this stays pure and
    /// disk-free for tests.
    static func evaluate(settings: [String: Any]?, fileExists: (String) -> Bool) -> HookStatus {
        guard
            let settings,
            let hooks = settings["hooks"] as? [String: Any],
            let stop = hooks["Stop"] as? [[String: Any]]
        else { return .notInstalled }

        for group in stop {
            guard let entries = group["hooks"] as? [[String: Any]] else { continue }
            for entry in entries {
                guard let command = entry["command"] as? String else { continue }
                for token in command.split(whereSeparator: { $0.isWhitespace }) {
                    if token.hasSuffix("mate-notify.js"), fileExists(String(token)) {
                        return .installed
                    }
                }
            }
        }
        return .notInstalled
    }

    /// Read `~/.claude/settings.json` and evaluate against the real filesystem.
    static func current() -> HookStatus {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        let settings: [String: Any]?
        if let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = object
        } else {
            settings = nil
        }
        return evaluate(settings: settings) { FileManager.default.fileExists(atPath: $0) }
    }
}
