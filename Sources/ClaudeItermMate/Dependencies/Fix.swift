import Foundation

/// The one action the Setup window offers for a checklist row.
///
/// Everything here is read-only guidance — open a page, activate an app, put a
/// command on the pasteboard — with two deliberate exceptions: `grantAutomation`
/// (macOS's own consent sheet) and `installHook` (our own file, our own hook).
/// We never run `uv tool install it2` and never write iTerm2's preferences for
/// the user: iTerm2 overwrites its plist from memory when it quits, so a
/// `defaults write` would look fixed now and silently revert on the next
/// restart — worse than doing nothing.
///
/// Lives next to `DependencyReport` rather than in `Setup/` because the
/// dependency is the one that knows how it is cured; the window only renders it.
enum Fix: Equatable {
    /// No action — a satisfied row.
    case none
    case openURL(URL, label: String)
    /// Copy to the pasteboard. `label` is spelled out per command because a
    /// one-line `uv tool install it2` reads well inline while the multi-part
    /// `uv` installer does not.
    case copyCommand(command: String, label: String)
    /// Bring iTerm2 to the front so the user can flip a setting inside it, or
    /// simply so it starts running and becomes checkable.
    case openIterm(label: String)
    /// Ask macOS for Apple Events permission (the native consent sheet).
    case grantAutomation
    /// Deep-link to System Settings › Privacy & Security › Automation, for when
    /// the user already answered "Don't Allow" and macOS will not ask again.
    case openPrivacySettings
    case installHook

    /// Button title, or nil when the row offers no action.
    var label: String? {
        switch self {
        case .none:
            return nil
        case .openURL(_, let label), .copyCommand(_, let label), .openIterm(let label):
            return label
        case .grantAutomation:
            return "Grant…"
        case .openPrivacySettings:
            return "Open Privacy Settings"
        case .installHook:
            return "Install Hook"
        }
    }
}
