import Foundation
import os

/// Answers "does this iTerm2 session still exist?" so the app can skip queuing
/// a tab (and skip the jump) for a reminder whose pane is already gone.
protocol ItermSessionProbe: Sendable {
    func canFind(_ uuid: String) -> Bool
    /// The full set of live iTerm2 session ids, or `nil` when it cannot be
    /// determined (probe unavailable / query failed). `nil` means "unknown", so
    /// callers must NOT treat it as "no sessions" — reconcile skips GC on `nil`.
    func liveSessionIDs() -> Set<String>?
}

extension ItermSessionProbe {
    /// Default: unknown. Concrete probes that can enumerate sessions override
    /// this; stubs inherit it and therefore never trigger reconcile GC.
    func liveSessionIDs() -> Set<String>? { nil }
}

/// Enumerates live iTerm2 sessions over **AppleScript** (`osascript`), NOT the
/// `it2` CLI: while a tab is in "Maximize Active Pane", the iTerm2 Python API —
/// and therefore `it2 session list` — reports only the maximized session, so
/// every other session looked un-findable (no jump on click, no tab, and
/// reconcile GC'd the live tabs). AppleScript enumerates the hidden panes too
/// (verified against a maximized tab: 6 sessions vs `it2`'s 1). When the query
/// fails a session is treated as NOT findable — so an unfindable reminder only
/// toasts and never becomes a dead, un-jumpable tab.
struct ItermSessionLookup: ItermSessionProbe {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermLookup")

    /// `is running` first so a probe never launches iTerm2; it yields no output
    /// (→ an empty set) when iTerm2 is not running, which is the truth: no panes.
    static let script = """
    if application "iTerm2" is running then
        tell application "iTerm2" to get id of every session of every tab of every window
    end if
    """

    let osascriptURL: URL

    init(osascriptURL: URL = URL(fileURLWithPath: "/usr/bin/osascript")) {
        self.osascriptURL = osascriptURL
    }

    func canFind(_ uuid: String) -> Bool {
        guard let ids = liveSessionIDs() else { return false }
        return ids.contains(uuid)
    }

    /// nil when the query fails; otherwise the set of live session ids.
    func liveSessionIDs() -> Set<String>? {
        let p = Process()
        p.executableURL = osascriptURL
        p.arguments = ["-e", Self.script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                Self.log.error("session enumeration exited \(p.terminationStatus)")
                return nil
            }
            return Self.parseSessionIDs(data)
        } catch {
            Self.log.error("session enumeration failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pure: extract session ids from the AppleScript list output, which is a
    /// single `, `-separated line (empty when iTerm2 is not running).
    static func parseSessionIDs(_ data: Data) -> Set<String> {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let ids = text
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Set(ids)
    }
}
