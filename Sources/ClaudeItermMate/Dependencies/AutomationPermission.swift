import AppKit
import CoreServices

/// May this app drive iTerm2 over Apple Events?
///
/// `ItermSessionLookup` enumerates live panes with `osascript`; without the
/// Automation grant that query fails, so reminders only ever toast and never
/// become tabs. The failure is completely silent today.
///
/// `AEDeterminePermissionToAutomateTarget` answers without sending a real event,
/// and with `askUserIfNeeded: false` it never pops a consent sheet — which is
/// what makes it safe to call from `DependencyReport.current()` and from the
/// Setup window's poll.
enum AutomationPermission {
    /// Pure mapping of the return codes. `noErr` and `procNotFound` were
    /// measured against a compiled probe (prd F7: iTerm2 running → 0; an
    /// installed-but-stopped app and a nonexistent bundle id → both -600). The
    /// two consent codes come from Apple's own definitions, not from a
    /// measurement — revoking a grant to observe them is destructive.
    static func state(for status: OSStatus) -> DependencyState {
        switch status {
        case noErr:
            return .ok
        // The user answered "Don't Allow". macOS will not ask again — only
        // System Settings can undo it.
        case OSStatus(errAEEventNotPermitted):
            return .missing
        // Never asked. Still missing, but the Grant… button can cure it.
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .missing
        // procNotFound: iTerm2 is not running. macOS returns the same code for
        // "not installed", but that case never gets here — we only ask once
        // LaunchServices has found iTerm2. Either way we observed no denial, so
        // this is "cannot tell", never "broken" (D4).
        case OSStatus(procNotFound):
            return .unknown
        default:
            return .unknown
        }
    }

    /// `askUserIfNeeded: true` shows macOS's own consent sheet and blocks until
    /// the user answers — call it off the main thread. `false` is a silent query.
    static func check(askUserIfNeeded: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: DependencyReport.itermBundleID)
        guard let descriptor = target.aeDesc else { return OSStatus(procNotFound) }
        // A wildcard class/id asks about the whole target rather than one verb,
        // which is what the TCC record actually covers.
        return AEDeterminePermissionToAutomateTarget(
            descriptor, typeWildCard, typeWildCard, askUserIfNeeded
        )
    }
}
