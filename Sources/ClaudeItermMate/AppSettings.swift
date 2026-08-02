import Foundation

/// User-facing toggles backed by `UserDefaults`, mirrored in the menu bar.
enum AppSettings {
    private static let showNonItermKey = "showNonItermSessions"

    /// Whether non-iTerm2 sessions are announced with a desktop notification.
    /// Default true: with it off, non-iTerm2 sessions are silent. They never
    /// appear as tabs — there is no pane to jump to.
    static var showNonIterm: Bool {
        get { UserDefaults.standard.object(forKey: showNonItermKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showNonItermKey) }
    }

    private static let colorPanesKey = "colorSessionPanes"

    /// Whether SessionStart sets the iTerm2 pane background to the project color.
    /// Default true. Off → panes are left at their default background.
    static var colorPanes: Bool {
        get { UserDefaults.standard.object(forKey: colorPanesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: colorPanesKey) }
    }

    private static let showTabStripKey = "showTabStrip"

    /// Whether reminders demote into a right-edge tab after their toast expires.
    /// Default true. Off → toasts still fly in, but expire without leaving a
    /// persistent tab (the strip stays empty).
    static var showTabStrip: Bool {
        get { UserDefaults.standard.object(forKey: showTabStripKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showTabStripKey) }
    }

    private static let playSoundKey = "playSound"

    /// Whether a system sound plays when a reminder toast appears. Default true.
    static var playSound: Bool {
        get { UserDefaults.standard.object(forKey: playSoundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: playSoundKey) }
    }

    private static let suppressSetupAtLaunchKey = "suppressSetupAtLaunch"

    /// Escape hatch for the Setup checklist window, ticked from inside it.
    /// Default false.
    ///
    /// It suppresses the *launch popup only*: the menu-bar warning triangle and
    /// the disabled warning rows stay exactly as they were, and Setup… still
    /// opens the window. "Stop interrupting me" is not "stop telling me".
    static var suppressSetupAtLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: suppressSetupAtLaunchKey) }
        set { UserDefaults.standard.set(newValue, forKey: suppressSetupAtLaunchKey) }
    }

    private static let hasReceivedEventKey = "hasReceivedHookEvent"

    /// One-way latch: true once ANY hook payload has ever reached the app.
    /// Diagnostic state, not a preference — deliberately absent from the menu.
    /// Backs `DependencyReport`'s delivery check (D2: detect the symptom, never
    /// probe `node`).
    static var hasReceivedEvent: Bool {
        get { UserDefaults.standard.bool(forKey: hasReceivedEventKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasReceivedEventKey) }
    }
}
