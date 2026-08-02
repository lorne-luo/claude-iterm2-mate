import Foundation

/// Where `uv` might live. Mirrors `ItermFocusAction`'s `it2` lookup on purpose:
/// a GUI-launched app inherits only launchd's `PATH` (`/usr/bin:/bin:/usr/sbin:
/// /sbin`), so probing by name is a guaranteed false negative — `uv` installs
/// into `~/.local/bin`, which is never on that PATH.
///
/// Only consulted when `it2` is unusable, since `uv` is purely the way `it2`
/// gets installed.
enum UvLocator {
    /// Absolute candidates in preference order: the `uv` installer's own target
    /// first, then the two Homebrew prefixes.
    static var candidates: [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/uv"),
            URL(fileURLWithPath: "/opt/homebrew/bin/uv"),
            URL(fileURLWithPath: "/usr/local/bin/uv"),
        ]
    }

    static func resolve() -> URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
