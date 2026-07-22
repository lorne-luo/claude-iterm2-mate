import Foundation

/// Installs the app's Claude Code hooks — the `mate-notify` Stop hook and the
/// `mate-session-start` SessionStart hook — by copying the bundled scripts to
/// a stable App Support path and registering them in `~/.claude/settings.json`.
struct HookInstaller {
    enum InstallError: Error {
        case bundledScriptMissing
        case settingsUnreadable
    }

    /// Stable install location for the script (alongside the notify socket).
    static var scriptDestURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeItermMate/mate-notify.js")
    }

    /// Install location for the SessionStart (color injection) hook script.
    static var sessionStartScriptDestURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeItermMate/mate-session-start.js")
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

    /// The Notification-hook command line: the same script in notification mode.
    static func notificationHookCommand(scriptPath: String) -> String {
        "node \"\(scriptPath)\" --event notification"
    }

    static func settingsByAddingHook(
        _ json: [String: Any],
        command: String,
        event: String = "Stop",
        marker: String = "mate-notify.js",
        matcher: String = ""
    ) -> [String: Any] {
        var settings = json
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var groups = hooks[event] as? [[String: Any]] ?? []

        for group in groups {
            for entry in group["hooks"] as? [[String: Any]] ?? [] {
                if let existing = entry["command"] as? String,
                   existing.contains(marker) {
                    return json
                }
            }
        }

        groups.append([
            "matcher": matcher,
            "hooks": [["type": "command", "command": command]],
        ])
        hooks[event] = groups
        settings["hooks"] = hooks
        return settings
    }

    /// Pure, unit-tested inverse of `settingsByAddingHook`. Drops every Stop
    /// hook entry whose command references `mate-notify.js`, removes any group
    /// left with no hooks, and preserves every other key, group and hook.
    /// Returns `json` unchanged when there is no `mate-notify.js` hook.
    static func settingsByRemovingHook(
        _ json: [String: Any],
        event: String = "Stop",
        marker: String = "mate-notify.js"
    ) -> [String: Any] {
        guard var hooks = json["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]]
        else { return json }

        var changed = false
        var newGroups: [[String: Any]] = []
        for var group in groups {
            let entries = group["hooks"] as? [[String: Any]] ?? []
            let kept = entries.filter { entry in
                !((entry["command"] as? String)?.contains(marker) ?? false)
            }
            if kept.count != entries.count { changed = true }
            if kept.isEmpty { continue } // drop emptied group
            group["hooks"] = kept
            newGroups.append(group)
        }
        guard changed else { return json }

        var settings = json
        hooks[event] = newGroups
        settings["hooks"] = hooks
        return settings
    }

    /// Copy the bundled scripts to App Support and register the Stop and
    /// SessionStart hooks.
    func install() throws {
        let fm = FileManager.default

        for (resource, dest) in [
            ("mate-notify", Self.scriptDestURL),
            ("mate-session-start", Self.sessionStartScriptDestURL),
        ] {
            guard let bundled = Bundle.module.url(forResource: resource, withExtension: "js") else {
                throw InstallError.bundledScriptMissing
            }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Atomically publish the script: copy to a sibling temp, then swap.
            // A plain remove-then-copy leaves a window where the script is
            // missing, during which a hook firing would error `MODULE_NOT_FOUND`.
            // Relevant because `install()` re-runs on every launch (upgrade path).
            let tmp = dest.appendingPathExtension("tmp-\(UUID().uuidString)")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: bundled, to: tmp)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        }

        let settingsURL = Self.settingsURL
        let current: [String: Any]
        if let data = try? Data(contentsOf: settingsURL),
           !data.isEmpty,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            current = object
        } else {
            current = [:]
        }

        var updated = Self.settingsByAddingHook(
            current, command: Self.hookCommand(scriptPath: Self.scriptDestURL.path)
        )
        updated = Self.settingsByAddingHook(
            updated,
            command: Self.hookCommand(scriptPath: Self.sessionStartScriptDestURL.path),
            event: "SessionStart",
            marker: "mate-session-start.js"
        )
        // The Notification hook reuses mate-notify.js in --event notification
        // mode, filtered to permission prompts. Marker is the script name so it
        // is app-specific: it matches our command (which contains the script
        // path) but never an unrelated hook that merely passes
        // `--event notification`, so we neither block its install nor delete it
        // on uninstall. Per-event scoping keeps it distinct from the Stop hook.
        updated = Self.settingsByAddingHook(
            updated,
            command: Self.notificationHookCommand(scriptPath: Self.scriptDestURL.path),
            event: "Notification",
            marker: "mate-notify.js",
            matcher: "permission_prompt"
        )
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(
            withJSONObject: updated,
            options: [.prettyPrinted, .sortedKeys]
        )
        data.append(0x0A) // trailing newline
        // Skip the write when nothing changed. `install()` re-runs on every
        // launch; a no-op write would churn the file's formatting and widen the
        // race window against another process editing settings.json.
        if (try? Data(contentsOf: settingsURL)) != data {
            try data.write(to: settingsURL)
        }
    }

    /// Remove both hooks from settings.json and delete the App Support copies
    /// of the scripts. No-op sections are tolerated (missing file / no hook).
    func uninstall() throws {
        let fm = FileManager.default
        let settingsURL = Self.settingsURL

        // Remove the hooks first. If settings.json exists but is non-empty and
        // unparseable, abort WITHOUT deleting the scripts — otherwise we'd
        // leave dangling `node <missing path>` hooks that error on every event.
        if let data = try? Data(contentsOf: settingsURL), !data.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.settingsUnreadable
            }
            var updated = Self.settingsByRemovingHook(object)
            updated = Self.settingsByRemovingHook(
                updated, event: "SessionStart", marker: "mate-session-start.js"
            )
            updated = Self.settingsByRemovingHook(
                updated, event: "Notification", marker: "mate-notify.js"
            )
            var out = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
            out.append(0x0A)
            try out.write(to: settingsURL)
        }

        for dest in [Self.scriptDestURL, Self.sessionStartScriptDestURL]
        where fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
    }
}
