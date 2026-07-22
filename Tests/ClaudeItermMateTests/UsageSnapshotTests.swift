import XCTest
@testable import ClaudeItermMate

final class UsageSnapshotTests: XCTestCase {
    func testDecodeRawApiBody() throws {
        let body = """
        {"five_hour":{"utilization":39,"resets_at":"2026-07-16T15:09:59.807Z"},
         "seven_day":{"utilization":9,"resets_at":"2026-07-21T12:59:59.807Z"},
         "seven_day_opus":{"utilization":4,"resets_at":"2026-07-21T12:59:59.807Z"}}
        """.data(using: .utf8)!
        let snap = try UsageSnapshot.decode(body)
        XCTAssertEqual(snap.fiveHour?.utilization, 39)
        XCTAssertEqual(snap.weekly?.utilization, 9)
        XCTAssertEqual(snap.weeklyOpus?.utilization, 4)
    }

    func testDecodeHudCacheBody() {
        let body = """
        {"data":{"planName":"Team","fiveHour":39,"sevenDay":9,
          "fiveHourResetAt":"2026-07-16T15:09:59.807Z",
          "sevenDayResetAt":"2026-07-21T12:59:59.807Z"},
         "timestamp":1784206024387}
        """.data(using: .utf8)!
        let snap = UsageSnapshot.decodeHudCache(body)
        XCTAssertEqual(snap?.fiveHour?.utilization, 39)
        XCTAssertEqual(snap?.weekly?.utilization, 9)
        XCTAssertNil(snap?.weeklyOpus, "hud cache carries no Opus window")
        XCTAssertNotNil(snap?.fiveHour?.resetsAt)
    }

    func testDecodeHudCacheApiUnavailableIsNil() {
        let body = """
        {"data":{"planName":"Team","fiveHour":null,"sevenDay":null,
          "fiveHourResetAt":null,"sevenDayResetAt":null,"apiUnavailable":true},
         "timestamp":1784206024387}
        """.data(using: .utf8)!
        XCTAssertNil(UsageSnapshot.decodeHudCache(body))
    }

    func testDecodeHudCacheMalformedIsNil() {
        XCTAssertNil(UsageSnapshot.decodeHudCache(Data("not json".utf8)))
    }

    func testClampHandlesNilNaNInfinityAndRange() {
        XCTAssertEqual(UsageSnapshot.clamp(nil), 0)
        XCTAssertEqual(UsageSnapshot.clamp(Double.nan), 0)
        XCTAssertEqual(UsageSnapshot.clamp(Double.infinity), 0)
        XCTAssertEqual(UsageSnapshot.clamp(-5), 0)
        XCTAssertEqual(UsageSnapshot.clamp(150), 100)
        XCTAssertEqual(UsageSnapshot.clamp(63.4), 63)
    }

    func testParseDateRejectsInvalidAndAcceptsBothIsoForms() {
        XCTAssertNil(UsageSnapshot.parseDate(nil))
        XCTAssertNil(UsageSnapshot.parseDate(""))
        XCTAssertNil(UsageSnapshot.parseDate("not-a-date"))
        XCTAssertNotNil(UsageSnapshot.parseDate("2026-07-16T15:09:59.807Z"))
        XCTAssertNotNil(UsageSnapshot.parseDate("2026-07-16T15:09:59Z"))
    }

    func testBadgeText() {
        func win(_ u: Int) -> UsageWindow { UsageWindow(utilization: u, resetsAt: nil) }
        XCTAssertEqual(
            UsageSnapshot(fiveHour: win(63), weekly: win(12), weeklyOpus: nil).badgeText,
            "5h 63% · 7d 12%")
        XCTAssertEqual(
            UsageSnapshot(fiveHour: win(63), weekly: nil, weeklyOpus: nil).badgeText, "5h 63%")
        XCTAssertEqual(
            UsageSnapshot(fiveHour: nil, weekly: win(12), weeklyOpus: nil).badgeText, "7d 12%")
        XCTAssertNil(UsageSnapshot(fiveHour: nil, weekly: nil, weeklyOpus: nil).badgeText)
    }

    func testDecodeRawApiWithOnlyFiveHour() throws {
        let body = """
        {"five_hour":{"utilization":50,"resets_at":"2026-07-16T15:09:59.807Z"}}
        """.data(using: .utf8)!
        let snap = try UsageSnapshot.decode(body)
        XCTAssertEqual(snap.fiveHour?.utilization, 50)
        XCTAssertNil(snap.weekly)
        XCTAssertNil(snap.weeklyOpus)
    }
}
