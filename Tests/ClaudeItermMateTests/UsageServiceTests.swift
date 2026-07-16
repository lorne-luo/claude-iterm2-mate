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
