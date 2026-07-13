import Foundation

/// Whether the `mate-notify` Stop hook is installed and its script is on disk.
enum HookStatus: Equatable {
    case installed
    case notInstalled

    /// Decide status from a parsed settings.json dict.
    ///
    /// Scans every `Stop` hook group's `hooks[].command` for one referencing
    /// `mate-notify.js`, extracts the absolute script path (from the first `/`
    /// through `mate-notify.js`, so paths containing spaces like
    /// "Application Support" survive), and returns `.installed` only when
    /// `fileExists` reports that path present. `fileExists` is injected so this
    /// stays pure and disk-free for tests.
    static func evaluate(settings: [String: Any]?, fileExists: (String) -> Bool) -> HookStatus {
        guard
            let settings,
            let hooks = settings["hooks"] as? [String: Any],
            let stop = hooks["Stop"] as? [[String: Any]]
        else { return .notInstalled }

        for group in stop {
            guard let entries = group["hooks"] as? [[String: Any]] else { continue }
            for entry in entries {
                guard let command = entry["command"] as? String,
                      let path = scriptPath(in: command),
                      fileExists(path)
                else { continue }
                return .installed
            }
        }
        return .notInstalled
    }

    /// The absolute `mate-notify.js` path referenced by a hook command, or nil.
    /// Takes the substring from the first `/` up to and including
    /// `mate-notify.js`, which keeps spaces in the path intact and ignores the
    /// `node ` prefix and any surrounding quotes.
    static func scriptPath(in command: String) -> String? {
        guard let scriptEnd = command.range(of: "mate-notify.js"),
              let firstSlash = command.firstIndex(of: "/"),
              firstSlash < scriptEnd.upperBound
        else { return nil }
        return String(command[firstSlash..<scriptEnd.upperBound])
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
