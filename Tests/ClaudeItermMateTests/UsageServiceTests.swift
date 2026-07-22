import XCTest
@testable import ClaudeItermMate

@MainActor
final class UsageServiceTests: XCTestCase {
    private func snap(_ five: Int) -> UsageSnapshot {
        UsageSnapshot(fiveHour: UsageWindow(utilization: five, resetsAt: nil), weekly: nil, weeklyOpus: nil)
    }

    // MARK: shouldFetch (pure rate-limit gate)

    func testShouldFetchTrueWhenNeverFetched() {
        XCTAssertTrue(UsageService.shouldFetch(last: nil, now: Date(), minInterval: 60))
    }

    func testShouldFetchFalseBeforeInterval() {
        let now = Date(timeIntervalSince1970: 1000)
        let last = now.addingTimeInterval(-59)
        XCTAssertFalse(UsageService.shouldFetch(last: last, now: now, minInterval: 60))
    }

    func testShouldFetchTrueAtInterval() {
        let now = Date(timeIntervalSince1970: 1000)
        let last = now.addingTimeInterval(-60)
        XCTAssertTrue(UsageService.shouldFetch(last: last, now: now, minInterval: 60))
    }

    func testShouldFetchTrueAfterInterval() {
        let now = Date(timeIntervalSince1970: 1000)
        let last = now.addingTimeInterval(-61)
        XCTAssertTrue(UsageService.shouldFetch(last: last, now: now, minInterval: 60))
    }

    // MARK: refreshIfStale (orchestration)

    func testRefreshRateLimitedToOncePerInterval() async {
        var t = Date(timeIntervalSince1970: 1000)
        var calls = 0
        let svc = UsageService(minInterval: 60, hudCachePath: "/nonexistent",
                               now: { t }, fetch: { _ in calls += 1; return self.snap(42) })
        await svc.refreshIfStale()?.value
        await svc.refreshIfStale()?.value            // same instant → gated
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(svc.snapshot?.fiveHour?.utilization, 42)
        t = t.addingTimeInterval(60)                 // interval elapsed
        await svc.refreshIfStale()?.value
        XCTAssertEqual(calls, 2)
    }

    func testRefreshKeepsPreviousSnapshotOnNilFetch() async {
        var results: [UsageSnapshot?] = [snap(7), nil]
        var t = Date(timeIntervalSince1970: 1000)
        let svc = UsageService(minInterval: 60, hudCachePath: "/nonexistent",
                               now: { t }, fetch: { _ in results.removeFirst() })
        await svc.refreshIfStale()?.value
        t = t.addingTimeInterval(60)
        await svc.refreshIfStale()?.value            // fetch returns nil
        XCTAssertEqual(svc.snapshot?.fiveHour?.utilization, 7, "nil fetch must not clobber a good snapshot")
    }

    func testRefreshGatedWhileFetchInFlight() async {
        // The task launched by refreshIfStale does not run until this @MainActor
        // method next suspends, so between the two synchronous calls below the
        // first fetch is provably still in flight. The second call must be gated by
        // the in-flight guard even though the rate-limit interval has elapsed.
        var calls = 0
        var t = Date(timeIntervalSince1970: 1000)
        let svc = UsageService(minInterval: 60, hudCachePath: "/nonexistent",
                               now: { t }, fetch: { _ in calls += 1; return self.snap(1) })
        let first = svc.refreshIfStale()          // task created & in flight; body not yet run
        t = t.addingTimeInterval(120)             // interval elapsed, yet a fetch is in flight
        XCTAssertNil(svc.refreshIfStale(), "must be gated while a fetch is in flight")
        await first?.value                        // first fetch now runs to completion
        XCTAssertEqual(calls, 1)
        await svc.refreshIfStale()?.value         // in-flight cleared → allowed again
        XCTAssertEqual(calls, 2)
    }

    func testRefreshPassesPreferHudFromFlag() async {
        var seen: Bool?
        let path = NSTemporaryDirectory() + "usage-svc-\(UUID().uuidString).json"
        FileManager.default.createFile(atPath: path, contents: Data("{}".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let svc = UsageService(minInterval: 60, hudCachePath: path,
                               now: { Date() }, fetch: { preferHud in seen = preferHud; return nil })
        svc.probeHudCache()
        XCTAssertTrue(svc.hudCacheAvailable)
        await svc.refreshIfStale()?.value
        XCTAssertEqual(seen, true, "flag=true must select the hud-cache path")
    }

    // MARK: probeHudCache

    func testProbeFalseWhenFileMissing() {
        let svc = UsageService(hudCachePath: "/definitely/not/here.json", fetch: { _ in nil })
        svc.probeHudCache()
        XCTAssertFalse(svc.hudCacheAvailable)
    }

    func testProbeTrueWhenFileExists() {
        let path = NSTemporaryDirectory() + "usage-probe-\(UUID().uuidString).json"
        FileManager.default.createFile(atPath: path, contents: Data("{}".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let svc = UsageService(hudCachePath: path, fetch: { _ in nil })
        svc.probeHudCache()
        XCTAssertTrue(svc.hudCacheAvailable)
    }
}
