import Foundation

struct NotifyPayload: Codable, Equatable {
    static let maxPayloadBytes = 1_048_576

    let sessionUUID: String
    let cwd: String
    let title: String
    let summary: String
    let fullMessage: String
    let timestamp: Double
    // Optional git context enriched by the Stop hook; absent for non-git dirs
    // and for payloads produced before this feature. Backward compatible.
    let repoRoot: String?
    let branch: String?
    // True when the session runs in a linked git worktree; absent -> false.
    let isWorktree: Bool
    // Message kind: absent for Stop notifications (backward compatible);
    // "session_start" for the SessionStart hook's color-injection trigger.
    let type: String?
    // SessionStart trigger ("startup" / "resume" / "clear"); absent otherwise.
    let source: String?
    // False for non-iTerm2 sessions: the app shows a dismiss-only tab (no pane
    // to jump to). Absent -> true (iTerm2 sessions, backward compatible).
    let focusable: Bool

    enum CodingKeys: String, CodingKey {
        case sessionUUID = "session_uuid"
        case cwd, title, summary
        case fullMessage = "full_message"
        case timestamp
        case repoRoot = "repo_root"
        case branch
        case isWorktree = "is_worktree"
        case type, source, focusable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionUUID = try c.decode(String.self, forKey: .sessionUUID)
        cwd = try c.decode(String.self, forKey: .cwd)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        fullMessage = try c.decode(String.self, forKey: .fullMessage)
        timestamp = try c.decode(Double.self, forKey: .timestamp)
        repoRoot = try c.decodeIfPresent(String.self, forKey: .repoRoot)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        isWorktree = try c.decodeIfPresent(Bool.self, forKey: .isWorktree) ?? false
        type = try c.decodeIfPresent(String.self, forKey: .type)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        focusable = try c.decodeIfPresent(Bool.self, forKey: .focusable) ?? true
    }

    var projectName: String { (cwd as NSString).lastPathComponent }

    var isSessionStart: Bool { type == "session_start" }

    static func decode(_ data: Data) -> NotifyPayload? {
        guard data.count <= maxPayloadBytes else { return nil }
        guard let p = try? JSONDecoder().decode(NotifyPayload.self, from: data) else { return nil }
        guard !p.sessionUUID.isEmpty, !p.cwd.isEmpty else { return nil }
        return p
    }
}
