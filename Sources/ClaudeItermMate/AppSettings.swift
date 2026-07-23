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
}
