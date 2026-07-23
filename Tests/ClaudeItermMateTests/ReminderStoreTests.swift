import XCTest
@testable import ClaudeItermMate

final class ReminderStoreTests: XCTestCase {
    private func payload(
        session: String = "S1", summary: String = "hi",
        repoRoot: String = "/tmp/proj", branch: String? = nil,
        timestamp: Double = 1.0, status: String? = nil
    ) -> NotifyPayload {
        var obj: [String: Any] = [
            "session_uuid": session, "cwd": repoRoot, "title": "[CC] proj",
            "summary": summary, "full_message": summary, "timestamp": timestamp,
            "repo_root": repoRoot,
        ]
        if let branch { obj["branch"] = branch }
        if let status { obj["status"] = status }
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: obj))!
    }

    func testUpsertCarriesStatus() {
        let store = ReminderStore()
        _ = store.upsert(payload())
        XCTAssertEqual(store.items[0].status, .completed, "no status field → completed")
        _ = store.upsert(payload(status: "waiting"))
        XCTAssertEqual(store.items[0].status, .waiting)
    }

    func testLaterCompletedPayloadReplacesWaitingStatus() {
        let store = ReminderStore()
        _ = store.upsert(payload(status: "waiting"))
        _ = store.upsert(payload(summary: "done")) // completed
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].status, .completed)
    }

    func testRefreshContentUpdatesFieldsButNotPhaseOrStatus() {
        let store = ReminderStore()
        let token = store.upsert(payload(summary: "old", status: "waiting"))
        store.queueIfCurrent(sessionUUID: "S1", token: token)
        store.refreshContent(sessionUUID: "S1", summary: "new", fullMessage: "new body", timestamp: 9.0, kind: .plain, questions: [])
        XCTAssertEqual(store.items[0].summary, "new")
        XCTAssertEqual(store.items[0].fullMessage, "new body")
        XCTAssertEqual(store.items[0].timestamp, 9.0)
        XCTAssertEqual(store.items[0].phase, .queued, "refresh must not re-enter the toast cycle")
        XCTAssertEqual(store.items[0].status, .waiting, "refresh must not change status")
    }

    func testRefreshContentIgnoresUnknownSession() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1"))
        store.refreshContent(sessionUUID: "NOPE", summary: "x", fullMessage: "x", timestamp: 2.0, kind: .plain, questions: [])
        XCTAssertEqual(store.items[0].summary, "hi", "unknown session is a no-op")
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

    func testUpsertDedupsBySessionAndLaterReplacesEarlier() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1", summary: "first", repoRoot: "/tmp/proj"))
        _ = store.upsert(payload(session: "S1", summary: "second", repoRoot: "/tmp/proj"))
        // Same session → one tab, carrying the later message.
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].sessionUUID, "S1")
        XCTAssertEqual(store.items[0].summary, "second")
    }

    func testConcurrentSessionsInSameDirGetSeparateTabs() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1", summary: "first", repoRoot: "/tmp/proj"))
        _ = store.upsert(payload(session: "S2", summary: "second", repoRoot: "/tmp/proj"))
        // Different sessions in the same directory each keep a tab.
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(Set(store.items.map(\.sessionUUID)), ["S1", "S2"])
    }

    func testSameDirSiblingsGetIncrementalLightenLevelsAndRecompactOnRemove() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1", repoRoot: "/tmp/proj", timestamp: 1.0))
        _ = store.upsert(payload(session: "S2", repoRoot: "/tmp/proj", timestamp: 2.0))
        _ = store.upsert(payload(session: "S3", repoRoot: "/tmp/proj", timestamp: 3.0))
        // Oldest keeps the base color; each newer one is one step lighter.
        func level(_ s: String) -> Int { store.items.first { $0.sessionUUID == s }!.lightenLevel }
        XCTAssertEqual(level("S1"), 0)
        XCTAssertEqual(level("S2"), 1)
        XCTAssertEqual(level("S3"), 2)
        // Removing the oldest recompacts survivors toward the base shade.
        store.remove(sessionUUID: "S1")
        XCTAssertEqual(level("S2"), 0)
        XCTAssertEqual(level("S3"), 1)
    }

    func testDifferentDirsEachStartAtBaseLevel() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1", repoRoot: "/tmp/alpha"))
        _ = store.upsert(payload(session: "S2", repoRoot: "/tmp/beta"))
        XCTAssertEqual(store.items.map(\.lightenLevel), [0, 0])
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
