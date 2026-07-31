import AppKit
import Foundation

/// Which of the app's external prerequisites are unmet, so the menu bar and a
/// first-run toast can say so instead of looking healthy while doing nothing.
///
/// `evaluate` is pure (every input injected) and holds all the logic; `current()`
/// is the only part that touches the real system.
struct DependencyReport {
    /// iTerm2's bundle id (verified: `osascript -e 'id of application "iTerm2"'`).
    static let itermBundleID = "com.googlecode.iterm2"

    enum Dependency {
        /// iTerm2 itself is not installed — the app degrades to a desktop notifier.
        case iterm2
        /// The `it2` CLI is missing, which also means no `iterm2`-capable Python.
        case it2
        /// The hook is installed but no payload has ever arrived (see D2: we detect
        /// the symptom, never probe `node` — a GUI app has only launchd's PATH).
        case delivery

        /// One disabled menu row, with the fix inline.
        var menuTitle: String {
            switch self {
            case .iterm2:
                return "iTerm2 not installed — download it from iterm2.com"
            case .it2:
                return "it2 not found — no jump, pane color, /color, question answers. Run: uv tool install it2"
            case .delivery:
                return "Hook installed but no events received — is node on Claude Code's PATH? Then restart Claude Code."
            }
        }

        /// One line of the startup toast's summary list.
        var toastLine: String {
            switch self {
            case .iterm2:
                return "• iTerm2 missing — reminders fall back to desktop notifications. Get it at iterm2.com"
            case .it2:
                return "• it2 missing — no jump, pane color, /color, question answers. Run: uv tool install it2"
            case .delivery:
                return "• No hook events received yet — check that node is on Claude Code's PATH, then restart it."
            }
        }
    }

    /// In declaration order, so the menu rows and the toast lines always agree.
    let missing: [Dependency]

    var hasAnyMissing: Bool { !missing.isEmpty }

    /// The pure core. `delivery` is deliberately NOT reported when the hook is
    /// not installed — that is "not opted in yet", not "broken".
    static func evaluate(
        itermInstalled: Bool,
        it2Found: Bool,
        hookInstalled: Bool,
        hasReceivedEvent: Bool
    ) -> DependencyReport {
        var missing: [Dependency] = []
        if !itermInstalled { missing.append(.iterm2) }
        if !it2Found { missing.append(.it2) }
        if hookInstalled && !hasReceivedEvent { missing.append(.delivery) }
        return DependencyReport(missing: missing)
    }

    /// Evaluate against the live system. `NSWorkspace` answers "installed?" with
    /// no subprocess — `ItermSessionLookup` cannot, since its `is running` guard
    /// yields an empty Set for both "not installed" and "no panes open".
    static func current() -> DependencyReport {
        evaluate(
            itermInstalled: NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: itermBundleID) != nil,
            it2Found: ItermFocusAction.resolveIt2() != nil,
            hookInstalled: HookStatus.current() == .installed,
            hasReceivedEvent: AppSettings.hasReceivedEvent
        )
    }
}
