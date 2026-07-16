import Foundation
import Observation

/// The single in-memory owner of the latest usage snapshot. Refreshes are
/// non-blocking (fire-and-forget `Task`) and rate-limited to one attempt per
/// `minInterval`. Source is chosen by `hudCacheAvailable`: read claude-hud's
/// local cache when present, else self-fetch from the OAuth usage API.
@MainActor
@Observable
final class UsageService {
    private(set) var snapshot: UsageSnapshot?
    private(set) var hudCacheAvailable = false
    private var lastAttemptAt: Date?

    private let minInterval: TimeInterval
    private let hudCachePath: String
    private let now: () -> Date
    private let fetch: (_ preferHud: Bool) async -> UsageSnapshot?

    // `nonisolated` so it can be used as an init default-argument value from a
    // nonisolated context (a plain constant needs no main-actor isolation).
    nonisolated static let defaultHudCachePath =
        NSString(string: "~/.claude/plugins/claude-hud/.usage-cache.json").expandingTildeInPath

    init(minInterval: TimeInterval = 60,
         hudCachePath: String = UsageService.defaultHudCachePath,
         now: @escaping () -> Date = { Date() },
         fetch: ((_ preferHud: Bool) async -> UsageSnapshot?)? = nil) {
        self.minInterval = minInterval
        self.hudCachePath = hudCachePath
        self.now = now
        self.fetch = fetch ?? { preferHud in
            await UsageService.defaultFetch(preferHud: preferHud, hudCachePath: hudCachePath)
        }
    }

    /// Cheap existence check for the claude-hud cache file. Called on each
    /// session_start; not rate-limited.
    func probeHudCache() {
        hudCacheAvailable = FileManager.default.fileExists(atPath: hudCachePath)
    }

    /// Pure rate-limit decision: fetch if never attempted, or the interval has
    /// fully elapsed.
    static func shouldFetch(last: Date?, now: Date, minInterval: TimeInterval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minInterval
    }

    /// If the rate-limit allows, stamp the attempt and launch the fetch (its
    /// blocking IO runs off the main actor inside defaultFetch).
    /// Returns the launched `Task` (nil when gated) so callers/tests can await
    /// completion; production callers ignore it (fire-and-forget). A nil result
    /// keeps the previous snapshot.
    @discardableResult
    func refreshIfStale() -> Task<Void, Never>? {
        let t = now()
        guard Self.shouldFetch(last: lastAttemptAt, now: t, minInterval: minInterval) else { return nil }
        lastAttemptAt = t
        let preferHud = hudCacheAvailable
        return Task { @MainActor [weak self] in
            guard let self else { return }
            if let snap = await self.fetch(preferHud) { self.snapshot = snap }
        }
    }

    /// Default IO. `preferHud` true → read the local cache file (no network, no
    /// Keychain); false → self-fetch from the OAuth usage API.
    static func defaultFetch(preferHud: Bool, hudCachePath: String) async -> UsageSnapshot? {
        if preferHud {
            // Data(contentsOf:) is a synchronous disk read — run it off the main
            // actor so the once-per-minute refresh never hitches the UI.
            return await Task.detached {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: hudCachePath)) else { return nil }
                return UsageSnapshot.decodeHudCache(data)
            }.value
        }
        // KeychainReader.readToken() forks `security` and blocks on
        // waitUntilExit(); run it off the main actor for the same reason.
        guard let token = await Task.detached(operation: { KeychainReader.readToken() }).value else { return nil }
        return await fetchFromApi(token: token)
    }

    private static func fetchFromApi(token: String) async -> UsageSnapshot? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/2.1", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? UsageSnapshot.decode(data)
    }
}
