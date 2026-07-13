import Foundation

/// Installs the `mate-notify` Stop hook: copies the bundled script to a stable
/// App Support path and registers it in `~/.claude/settings.json`.
struct HookInstaller {
    enum InstallError: Error {
        case bundledScriptMissing
    }

    /// Stable install location for the script (alongside the notify socket).
    static var scriptDestURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeItermMate/mate-notify.js")
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// Pure, unit-tested settings transform. Returns `json` unchanged if any
    /// existing Stop hook command already references `mate-notify.js`;
    /// otherwise appends a new group with `command`, creating the `hooks` /
    /// `Stop` containers when absent and preserving every other key, group and
    /// hook.
    /// The Stop hook command line. The script path is quoted because the App
    /// Support path contains a space ("Application Support"); an unquoted path
    /// makes `node` treat the first segment as the module and fail with
    /// MODULE_NOT_FOUND.
    static func hookCommand(scriptPath: String) -> String {
        "node \"\(scriptPath)\""
    }

    static func settingsByAddingHook(_ json: [String: Any], command: String) -> [String: Any] {
        var settings = json
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var stop = hooks["Stop"] as? [[String: Any]] ?? []

        for group in stop {
            for entry in group["hooks"] as? [[String: Any]] ?? [] {
                if let existing = entry["command"] as? String,
                   existing.contains("mate-notify.js") {
                    return json
                }
            }
        }

        stop.append([
            "matcher": "",
            "hooks": [["type": "command", "command": command]],
        ])
        hooks["Stop"] = stop
        settings["hooks"] = hooks
        return settings
    }

    /// Copy the bundled script to `scriptDestURL` and register the Stop hook.
    func install() throws {
        let fm = FileManager.default
        guard let bundled = Bundle.module.url(forResource: "mate-notify", withExtension: "js") else {
            throw InstallError.bundledScriptMissing
        }

        let dest = Self.scriptDestURL
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: bundled, to: dest)

        let settingsURL = Self.settingsURL
        let current: [String: Any]
        if let data = try? Data(contentsOf: settingsURL),
           !data.isEmpty,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            current = object
        } else {
            current = [:]
        }

        let updated = Self.settingsByAddingHook(current, command: Self.hookCommand(scriptPath: dest.path))
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(
            withJSONObject: updated,
            options: [.prettyPrinted, .sortedKeys]
        )
        data.append(0x0A) // trailing newline
        try data.write(to: settingsURL)
    }
}
