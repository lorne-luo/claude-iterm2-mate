import Foundation
import Observation

enum ReminderPhase: Equatable {
    case toasting(token: UUID)
    case queued
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

    var id: String { sessionUUID }
    var identity: ReminderIdentity { ReminderIdentity(repoRoot: repoRoot, branch: branch, cwd: cwd) }
    var projectName: String { identity.project }
}

@Observable
final class ReminderStore {
    private(set) var items: [ReminderItem] = []

    var queued: [ReminderItem] { items.filter { $0.phase == .queued } }

    /// Insert or update the reminder for a project and start a new toast
    /// cycle. Dedup is by project path (`identity.key`): a later message for
    /// the same project removes the earlier tab and inserts the new one at the
    /// top, so a project has at most one tab. Returns the toast token;
    /// `queueIfCurrent` only acts when the token still matches, so a replaced
    /// toast's timer can never fire.
    @discardableResult
    func upsert(_ p: NotifyPayload) -> UUID {
        let token = UUID()
        let item = ReminderItem(
            sessionUUID: p.sessionUUID,
            cwd: p.cwd,
            repoRoot: p.repoRoot,
            branch: p.branch,
            isWorktree: p.isWorktree,
            summary: p.summary,
            fullMessage: p.fullMessage,
            timestamp: p.timestamp,
            phase: .toasting(token: token)
        )
        items.removeAll { $0.identity.key == item.identity.key }
        items.insert(item, at: 0)
        return token
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
    }

    func remove(sessionUUID: String) {
        items.removeAll { $0.sessionUUID == sessionUUID }
    }

    func removeAll() {
        items.removeAll()
    }
}
