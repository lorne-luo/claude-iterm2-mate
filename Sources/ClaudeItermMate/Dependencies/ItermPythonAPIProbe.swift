import Foundation

/// Is iTerm2's Python API switched on?
///
/// This is the blind spot that motivated the whole Setup checklist: `it2` can be
/// installed, its interpreter can import `iterm2`, and every single it2-powered
/// action still fails — `it2 session list` answers "Not running inside iTerm2 or
/// Python API not enabled." The API ships **off**.
///
/// Read straight out of iTerm2's preferences domain: no subprocess, and nothing
/// that could launch iTerm2. Cheap enough for the Setup window's 2 s poll.
enum ItermPythonAPIProbe {
    static let domain = DependencyReport.itermBundleID as CFString

    private static let enableKey = "EnableAPIServer" as CFString
    /// Set when the user points iTerm2 at a preferences folder of their own, in
    /// which case the standard domain is not where the truth lives.
    private static let customFolderKey = "LoadPrefsFromCustomFolder" as CFString

    /// The API server's unix socket, created when the server comes up.
    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iTerm2/private/socket")
    }

    /// Pure decision.
    ///
    /// The socket is a one-way proof: present means the API server is running,
    /// so the answer is yes no matter what the plist says. It is deliberately
    /// **not** the primary check — it is also absent whenever iTerm2 simply is
    /// not running, which would read as "disabled". Without this OR, a user who
    /// ticks the box while the window is open could sit through any number of
    /// 2 s polls waiting for iTerm2 to flush its preferences to disk.
    static func state(
        rawEnableAPIServer: Any?,
        socketExists: Bool,
        customPrefsFolder: Bool
    ) -> DependencyState {
        if socketExists { return .ok }
        // We read the standard domain; with a custom folder in play a "disabled"
        // reading there proves nothing, so say so rather than cry wolf.
        if customPrefsFolder { return .unknown }
        // NSNumber/CFBoolean both bridge through `as? Bool`. The key is absent
        // until the user first touches the toggle, and the shipped default is
        // off — so absent is genuinely "disabled", not "cannot tell".
        guard let raw = rawEnableAPIServer else { return .missing }
        guard let enabled = raw as? Bool else { return .unknown }
        return enabled ? .ok : .missing
    }

    static func current() -> DependencyState {
        // Drop cfprefsd's cached copy first: iTerm2 writes the plist from another
        // process, and a stale read is exactly the "ticked it, still red" bug.
        CFPreferencesAppSynchronize(domain)
        return state(
            rawEnableAPIServer: CFPreferencesCopyAppValue(enableKey, domain),
            socketExists: FileManager.default.fileExists(atPath: socketURL.path),
            customPrefsFolder: CFPreferencesCopyAppValue(customFolderKey, domain) as? Bool ?? false
        )
    }
}
