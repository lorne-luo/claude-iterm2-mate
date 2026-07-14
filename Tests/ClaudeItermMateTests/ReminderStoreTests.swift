import XCTest
@testable import ClaudeItermMate

final class ReminderStoreTests: XCTestCase {
    private func payload(
        session: String = "S1", summary: String = "hi",
        repoRoot: String = "/tmp/proj", branch: String? = nil
    ) -> NotifyPayload {
        var obj: [String: Any] = [
            "session_uuid": session, "cwd": repoRoot, "title": "[CC] proj",
            "summary": summary, "full_message": summary, "timestamp": 1.0,
            "repo_root": repoRoot,
        ]
        if let branch { obj["branch"] = branch }
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: obj))!
    }

    func testUpsertInsertsAsToasting() {
        let store = ReminderStore()
        let token = store.upsert(payload())
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].phase, .toasting(token: token))
        XCTAssertTrue(store.queued.isEmpty)
    }

    func testQueueIfCurrentMovesToQueued() {
        let store = ReminderStore()
        let token = store.upsert(payload())
        store.queueIfCurrent(sessionUUID: "S1", token: token)
        XCTAssertEqual(store.queued.count, 1)
        XCTAssertEqual(store.queued[0].phase, .queued)
    }

    func testStaleTokenDoesNotQueue() {
        let store = ReminderStore()
        let old = store.upsert(payload(summary: "first"))
        _ = store.upsert(payload(summary: "second")) // same session, new toast
        store.queueIfCurrent(sessionUUID: "S1", token: old)
        XCTAssertTrue(store.queued.isEmpty) // stale timer must never fire
        XCTAssertEqual(store.items[0].summary, "second")
    }

    func testUpsertDedupsByProjectAndLaterReplacesEarlier() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1", summary: "first", repoRoot: "/tmp/proj"))
        _ = store.upsert(payload(session: "S2", summary: "second", repoRoot: "/tmp/proj"))
        // Same project, different session → one tab, carrying the later message.
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].sessionUUID, "S2")
        XCTAssertEqual(store.items[0].summary, "second")
    }

    func testDifferentProjectsKeepSeparateTabs() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1", repoRoot: "/tmp/alpha"))
        _ = store.upsert(payload(session: "S2", repoRoot: "/tmp/beta"))
        XCTAssertEqual(store.items.count, 2)
    }

    func testWorktreesOfSameRepoStaySeparate() {
        // Worktrees report distinct repo_root → distinct tabs, one per worktree.
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1", repoRoot: "/tmp/proj", branch: "main"))
        _ = store.upsert(payload(session: "S2", repoRoot: "/tmp/proj/.worktree/feat", branch: "feat"))
        XCTAssertEqual(store.items.count, 2)
    }

    func testRemove() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1", repoRoot: "/tmp/alpha"))
        _ = store.upsert(payload(session: "S2", repoRoot: "/tmp/beta"))
        store.remove(sessionUUID: "S1")
        XCTAssertEqual(store.items.map(\.sessionUUID), ["S2"])
        store.removeAll()
        XCTAssertTrue(store.items.isEmpty)
    }
}
