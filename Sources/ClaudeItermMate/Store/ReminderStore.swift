import Foundation
import Observation

enum ReminderPhase: Equatable {
    case toasting(token: UUID)
    case queued
}

/// Whether a reminder is a plain notification/permission wait or an
/// AskUserQuestion prompt (which carries `questions` and renders answer
/// controls). Orthogonal to `status`; a question is always `.waiting`.
enum ReminderKind: Equatable {
    case plain
    case question
}

struct ReminderItem: Identifiable, Equatable {
    let sessionUUID: String
    var cwd: String
    var repoRoot: String?
    var branch: String?
    var isWorktree: Bool
    var summary: String
    var fullMessage: String
    var timestamp: Double
    var phase: ReminderPhase
    /// Completed ("look when you can") vs waiting ("blocked, act now"). Drives
    /// the amber tab accent. Orthogonal to `phase`.
    var status: SessionStatus
    /// Plain vs AskUserQuestion. Drives whether answer controls render.
    var kind: ReminderKind
    /// AskUserQuestion questions + options (empty unless `kind == .question`).
    var questions: [NotifyPayload.Question]
    /// Palette slot + worktree lighten level, assigned by the shared
    /// `ColorAssigner` at upsert so tabs match the injected `/color` name.
    var colorIndex: Int
    var lightenLevel: Int
    /// False for non-iTerm2 sessions: the tab/toast is dismiss-only (there is
    /// no iTerm2 pane to jump to).
    var focusable: Bool

    var id: String { sessionUUID }
    var identity: ReminderIdentity { ReminderIdentity(repoRoot: repoRoot, branch: branch, cwd: cwd) }
    /// The lone question when this reminder is an interactive single-question
    /// AskUserQuestion; nil for plain reminders and multi-question prompts (which
    /// render as text). Shared by DetailView and ToastView — the tty injection
    /// sequence is only verified for a single question.
    var interactiveQuestion: NotifyPayload.Question? {
        guard kind == .question, questions.count == 1 else { return nil }
        return questions.first
    }
    var projectName: String { identity.project }
    /// Branch name for a normal checkout; worktree path (shorter of relative /
    /// absolute) for a linked worktree. Nil when there is nothing to show.
    var branchLabel: String? {
        ReminderIdentity.locationLabel(repoRoot: repoRoot, cwd: cwd, branch: branch, isWorktree: isWorktree)
    }
}

@Observable
final class ReminderStore {
    private(set) var items: [ReminderItem] = []

    /// Shared color authority — the same instance drives `/color` injection,
    /// so tab colors and prompt-bar colors stay in sync.
    let assigner: ColorAssigner

    init(assigner: ColorAssigner = ColorAssigner()) {
        self.assigner = assigner
    }

    var queued: [ReminderItem] { items.filter { $0.phase == .queued } }

    /// Insert or update the reminder for a session and start a new toast
    /// cycle. Dedup is by session UUID: a later message for the same session
    /// replaces its own tab, but concurrent sessions in the same directory
    /// each keep a tab, distinguished by lighten level. Returns the toast
    /// token; `queueIfCurrent` only acts when the token still matches, so a
    /// replaced toast's timer can never fire.
    @discardableResult
    func upsert(_ p: NotifyPayload) -> UUID {
        let token = UUID()
        let identity = ReminderIdentity(repoRoot: p.repoRoot, branch: p.branch, cwd: p.cwd)
        let item = ReminderItem(
            sessionUUID: p.sessionUUID,
            cwd: p.cwd,
            repoRoot: p.repoRoot,
            branch: p.branch,
            isWorktree: p.isWorktree,
            summary: p.summary,
            fullMessage: p.fullMessage,
            timestamp: p.timestamp,
            phase: .toasting(token: token),
            status: p.sessionStatus,
            kind: p.isQuestion ? .question : .plain,
            questions: p.questions ?? [],
            colorIndex: assigner.colorIndex(for: identity.key),
            lightenLevel: 0,
            focusable: p.focusable
        )
        items.removeAll { $0.sessionUUID == p.sessionUUID }
        items.insert(item, at: 0)
        reassignLightenLevels()
        return token
    }

    /// Siblings sharing a base color (same `identity.key`) get incremental
    /// lighten levels so concurrent same-directory sessions are
    /// distinguishable. Ordered by `(timestamp, sessionUUID)` ascending, the
    /// oldest session keeps the base color (level 0) and each newer one is one
    /// step lighter. Computed over all items so a toasting newcomer's shade is
    /// fixed before it becomes a tab and existing tabs never shift. Levels
    /// beyond the palette's factor table clamp in `ReminderPalette.components`.
    private func reassignLightenLevels() {
        let groups = Dictionary(grouping: items.indices) { items[$0].identity.key }
        for (_, idxs) in groups {
            let ordered = idxs.sorted {
                (items[$0].timestamp, items[$0].sessionUUID) < (items[$1].timestamp, items[$1].sessionUUID)
            }
            for (level, i) in ordered.enumerated() { items[i].lightenLevel = level }
        }
    }

    /// Update an existing item's content in place (summary/message/timestamp)
    /// without touching its phase, token, status, or color. Used when a session
    /// already showing a waiting state gets a follow-up waiting event: the tab
    /// refreshes but must not re-enter the toast cycle (no new token) or vanish
    /// from the strip (phase stays `.queued`). No-op if the session is unknown.
    func refreshContent(
        sessionUUID: String,
        summary: String,
        fullMessage: String,
        timestamp: Double,
        kind: ReminderKind,
        questions: [NotifyPayload.Question]
    ) {
        guard let i = items.firstIndex(where: { $0.sessionUUID == sessionUUID }) else { return }
        items[i].summary = summary
        items[i].fullMessage = fullMessage
        items[i].timestamp = timestamp
        items[i].kind = kind
        items[i].questions = questions
    }

    func queueIfCurrent(sessionUUID: String, token: UUID) {
        guard let i = items.firstIndex(where: { $0.sessionUUID == sessionUUID }),
              items[i].phase == .toasting(token: token) else { return }
        items[i].phase = .queued
    }

    /// Drop a still-toasting item — used when its iTerm2 session is not
    /// findable, so it never becomes a tab. Token-guarded like `queueIfCurrent`
    /// so a newer toast that replaced it is never removed by a stale timer.
    func removeIfCurrent(sessionUUID: String, token: UUID) {
        guard let i = items.firstIndex(where: { $0.sessionUUID == sessionUUID }),
              items[i].phase == .toasting(token: token) else { return }
        items.remove(at: i)
        reassignLightenLevels()
    }

    func remove(sessionUUID: String) {
        items.removeAll { $0.sessionUUID == sessionUUID }
        reassignLightenLevels()
    }

    func removeAll() {
        items.removeAll()
    }
}
