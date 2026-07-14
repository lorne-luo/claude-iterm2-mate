import Foundation

/// User-facing toggles backed by `UserDefaults`, mirrored in the menu bar.
enum AppSettings {
    private static let showNonItermKey = "showNonItermSessions"

    /// Whether non-iTerm2 sessions appear as dismiss-only tabs in the app.
    /// Default true: with it off, non-iTerm2 sessions get a plain desktop
    /// notification instead (the pre-feature behavior).
    static var showNonIterm: Bool {
        get { UserDefaults.standard.object(forKey: showNonItermKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showNonItermKey) }
    }
}
