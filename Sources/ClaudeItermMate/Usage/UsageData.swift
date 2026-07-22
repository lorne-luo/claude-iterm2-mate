import Foundation

/// One usage window's state (a 5-hour or 7-day rolling limit).
/// `utilization` is the server-computed percentage 0–100; the denominator is
/// not public, so we take the value as-is rather than deriving it locally.
struct UsageWindow: Equatable {
    let utilization: Int      // 0–100
    let resetsAt: Date?       // nil when the API omits it (window inactive / N/A)
}

/// Parsed snapshot of the OAuth usage API (`GET /api/oauth/usage`).
/// Only the windows this app displays are kept; the API returns more.
struct UsageSnapshot: Equatable {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    let weeklyOpus: UsageWindow?

    /// Compact `5h N% · 7d N%` label for the toast/detail title rows, or nil
    /// when neither window has data (callers then render no badge). weeklyOpus
    /// is intentionally not shown.
    var badgeText: String? {
        var parts: [String] = []
        if let fiveHour { parts.append("5h \(fiveHour.utilization)%") }
        if let weekly { parts.append("7d \(weekly.utilization)%") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Decode from the raw API response body. Pure/testable.
    static func decode(_ data: Data) throws -> UsageSnapshot {
        let raw = try JSONDecoder().decode(RawResponse.self, from: data)
        return UsageSnapshot(
            fiveHour: raw.fiveHour?.toWindow(),
            weekly: raw.sevenDay?.toWindow(),
            weeklyOpus: raw.sevenDayOpus?.toWindow()
        )
    }

    /// Decode claude-hud's local cache file (`.usage-cache.json`), which stores
    /// an already-normalized `UsageData` under `data` (camelCase 0–100 ints).
    /// Returns nil for a failure-cache (`apiUnavailable == true`), an empty
    /// snapshot (both windows absent), or malformed input — so a bad file leaves
    /// the caller's existing snapshot untouched.
    static func decodeHudCache(_ data: Data) -> UsageSnapshot? {
        guard let file = try? JSONDecoder().decode(HudCacheFile.self, from: data) else { return nil }
        let d = file.data
        if d.apiUnavailable == true { return nil }
        let five = d.fiveHour.map {
            UsageWindow(utilization: clamp(Double($0)), resetsAt: parseDate(d.fiveHourResetAt))
        }
        let weekly = d.sevenDay.map {
            UsageWindow(utilization: clamp(Double($0)), resetsAt: parseDate(d.sevenDayResetAt))
        }
        guard five != nil || weekly != nil else { return nil }
        return UsageSnapshot(fiveHour: five, weekly: weekly, weeklyOpus: nil)
    }

    // MARK: - Raw wire shape

    private struct RawResponse: Decodable {
        let fiveHour: RawWindow?
        let sevenDay: RawWindow?
        let sevenDayOpus: RawWindow?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
        }
    }

    private struct RawWindow: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        func toWindow() -> UsageWindow {
            UsageWindow(
                utilization: UsageSnapshot.clamp(utilization),
                resetsAt: UsageSnapshot.parseDate(resetsAt)
            )
        }
    }

    /// Clamp to 0–100, treating nil / NaN / Infinity as 0.
    static func clamp(_ value: Double?) -> Int {
        guard let value, value.isFinite else { return 0 }
        return Int(max(0, min(100, value.rounded())))
    }

    /// Parse an ISO 8601 timestamp; nil for missing or invalid input.
    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return isoWithFraction.date(from: string) ?? isoPlain.date(from: string)
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private struct HudCacheFile: Decodable {
        let data: HudData
        struct HudData: Decodable {
            let fiveHour: Int?
            let sevenDay: Int?
            let fiveHourResetAt: String?
            let sevenDayResetAt: String?
            let apiUnavailable: Bool?
        }
    }
}
