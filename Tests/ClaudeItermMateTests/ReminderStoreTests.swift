import XCTest
@testable import ClaudeItermMate

final class ReminderStoreTests: XCTestCase {
    private func payload(session: String = "S1", summary: String = "hi") -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: [
            "session_uuid": session, "cwd": "/tmp/proj", "title": "[CC] proj",
            "summary": summary, "full_message": summary, "timestamp": 1.0,
        ]))!
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

    func testUpsertDedupsBySessionAndMovesToTop() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1"))
        _ = store.upsert(payload(session: "S2"))
        _ = store.upsert(payload(session: "S1", summary: "updated"))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items[0].sessionUUID, "S1")
        XCTAssertEqual(store.items[0].summary, "updated")
    }

    func testRemove() {
        let store = ReminderStore()
        _ = store.upsert(payload(session: "S1"))
        _ = store.upsert(payload(session: "S2"))
        store.remove(sessionUUID: "S1")
        XCTAssertEqual(store.items.map(\.sessionUUID), ["S2"])
        store.removeAll()
        XCTAssertTrue(store.items.isEmpty)
    }
}
