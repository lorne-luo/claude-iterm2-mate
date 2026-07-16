import Foundation

/// Reads the Claude Code OAuth access token from the macOS Keychain.
/// Mirrors claude-hud: `security find-generic-password -s "Claude Code-credentials" -w`
/// returns a JSON blob whose `claudeAiOauth.accessToken` is the bearer token.
/// Only the default `~/.claude` config is supported (no custom-config hashing,
/// no `.credentials.json` file fallback).
enum KeychainReader {
    static let service = "Claude Code-credentials"

    private struct CredentialsFile: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?   // Unix ms
        }
        let claudeAiOauth: OAuth?
    }

    /// Pure: extract an unexpired access token from the Keychain JSON blob.
    /// Returns nil when the token is missing, or `expiresAt` (Unix ms) is at or
    /// before `now`. A token without `expiresAt` is accepted.
    static func parseAccessToken(json: Data, now: Date) -> String? {
        guard let file = try? JSONDecoder().decode(CredentialsFile.self, from: json),
              let token = file.claudeAiOauth?.accessToken, !token.isEmpty else {
            return nil
        }
        if let expiresAtMs = file.claudeAiOauth?.expiresAt {
            let nowMs = now.timeIntervalSince1970 * 1000
            if expiresAtMs <= nowMs { return nil }
        }
        return token
    }

    /// Run `/usr/bin/security` and parse its stdout. `runSecurity` is injectable
    /// for tests; the default shells out on macOS and returns nil elsewhere/on
    /// failure. Security: `Process` with an absolute path and argument array
    /// (no shell), so there is no injection surface.
    static func readToken(now: Date = Date(),
                          runSecurity: () -> Data? = KeychainReader.defaultRunSecurity) -> String? {
        guard let out = runSecurity() else { return nil }
        return parseAccessToken(json: out, now: now)
    }

    static func defaultRunSecurity() -> Data? {
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0, !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
