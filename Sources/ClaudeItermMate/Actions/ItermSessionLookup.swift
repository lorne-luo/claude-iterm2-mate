import Foundation
import os

/// Answers "does this iTerm2 session still exist?" so the app can skip queuing
/// a tab (and skip the jump) for a reminder whose pane is already gone.
protocol ItermSessionProbe: Sendable {
    func canFind(_ uuid: String) -> Bool
}

/// Queries live iTerm2 sessions via the `it2` CLI (`session list --json`),
/// whose objects carry the same session `id` we jump to. When `it2` is missing
/// or the query fails, a session is treated as NOT findable — so an unfindable
/// reminder only toasts and never becomes a dead, un-jumpable tab.
struct ItermSessionLookup: ItermSessionProbe {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermLookup")

    let it2URL: URL?

    init(it2URL: URL? = ItermFocusAction.resolveIt2()) {
        self.it2URL = it2URL
    }

    func canFind(_ uuid: String) -> Bool {
        guard let ids = liveSessionIDs() else { return false }
        return ids.contains(uuid)
    }

    /// nil when `it2` is unavailable or the query fails; otherwise the set of
    /// live session ids.
    func liveSessionIDs() -> Set<String>? {
        guard let it2URL else { return nil }
        let p = Process()
        p.executableURL = it2URL
        p.arguments = ["session", "list", "--json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return Self.parseSessionIDs(data)
        } catch {
            Self.log.error("it2 session list failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pure: extract session ids from `it2 session list --json` output.
    static func parseSessionIDs(_ data: Data) -> Set<String> {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return Set(arr.compactMap { $0["id"] as? String })
    }
}
