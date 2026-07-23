import Foundation

struct NotifyPayload: Codable, Equatable {
    static let maxPayloadBytes = 1_048_576

    /// A single AskUserQuestion question with its options (from `--event ask`).
    struct Question: Codable, Equatable {
        let question: String
        let header: String
        let multiSelect: Bool
        let options: [Option]

        struct Option: Codable, Equatable {
            let label: String
            let description: String
        }
    }

    let sessionUUID: String
    let cwd: String
    // title/summary/fullMessage are absent on the minimal `resolve` payload
    // (`--event ask-done`), so they decode with a "" default; every other event
    // always supplies them.
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
    // Message kind: "stop" for a genuine Stop event (older hooks omit it →
    // still handled as a Stop, but they cannot inject /color, see `isStop`);
    // "session_start" for the SessionStart hook's color trigger; "question" for
    // an AskUserQuestion PreToolUse; "resolve" for its PostToolUse (clear the
    // waiting tab); absent for a permission-prompt Notification.
    let type: String?
    // AskUserQuestion questions + options (only on `type == "question"`).
    let questions: [Question]?
    // SessionStart trigger ("startup" / "resume" / "clear"); absent otherwise.
    let source: String?
    // False for non-iTerm2 sessions: the app shows a dismiss-only tab (no pane
    // to jump to). Absent -> true (iTerm2 sessions, backward compatible).
    let focusable: Bool
    // "waiting" when the session needs the user to act (permission prompt, or a
    // Stop whose reply ends in a question); absent / anything else -> completed.
    // Backward compatible: old payloads without this field decode as completed.
    let status: String?

    enum CodingKeys: String, CodingKey {
        case sessionUUID = "session_uuid"
        case cwd, title, summary
        case fullMessage = "full_message"
        case timestamp
        case repoRoot = "repo_root"
        case branch
        case isWorktree = "is_worktree"
        case type, source, focusable, status, questions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionUUID = try c.decode(String.self, forKey: .sessionUUID)
        cwd = try c.decode(String.self, forKey: .cwd)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        fullMessage = try c.decodeIfPresent(String.self, forKey: .fullMessage) ?? ""
        timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp) ?? 0
        repoRoot = try c.decodeIfPresent(String.self, forKey: .repoRoot)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        isWorktree = try c.decodeIfPresent(Bool.self, forKey: .isWorktree) ?? false
        type = try c.decodeIfPresent(String.self, forKey: .type)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        focusable = try c.decodeIfPresent(Bool.self, forKey: .focusable) ?? true
        status = try c.decodeIfPresent(String.self, forKey: .status)
        questions = try c.decodeIfPresent([Question].self, forKey: .questions)
    }

    var projectName: String { (cwd as NSString).lastPathComponent }

    var isSessionStart: Bool { type == "session_start" }

    /// A genuine Stop event (turn finished, pane back at an ordinary composer).
    /// The one event where injecting `/color` keystrokes is safe — unlike a
    /// permission prompt or AskUserQuestion, which show a live TUI.
    var isStop: Bool { type == "stop" }

    /// AskUserQuestion PreToolUse event (carries `questions`).
    var isQuestion: Bool { type == "question" }

    /// AskUserQuestion answered (PostToolUse): the app removes the waiting tab.
    var isResolve: Bool { type == "resolve" }

    /// Parsed status; absent / unknown -> `.completed` (backward compatible).
    var sessionStatus: SessionStatus { SessionStatus(wire: status) }

    static func decode(_ data: Data) -> NotifyPayload? {
        guard data.count <= maxPayloadBytes else { return nil }
        guard let p = try? JSONDecoder().decode(NotifyPayload.self, from: data) else { return nil }
        guard !p.sessionUUID.isEmpty, !p.cwd.isEmpty else { return nil }
        return p
    }
}
