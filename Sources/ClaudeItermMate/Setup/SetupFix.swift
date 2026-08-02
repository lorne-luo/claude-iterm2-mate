import AppKit

/// Executes a checklist row's action. Everything here is read-only guidance
/// except the two cases we own outright: macOS's own Automation consent sheet,
/// and our own hook installer.
///
/// In particular this never runs `uv tool install it2` for the user (an
/// unattended installer writing to their PATH), and never writes iTerm2's
/// preferences (iTerm2 rewrites its plist from memory on quit, so the setting
/// would silently revert — looking fixed and coming back broken is worse than
/// telling the user where the checkbox is).
@MainActor
enum SetupFix {
    enum Outcome: Equatable {
        case done
        /// The user has already answered "Don't Allow", so macOS will not put
        /// the sheet up again — only System Settings can undo it.
        case automationDenied
    }

    /// `completion` runs on the main actor once the action has been kicked off
    /// (or, for the consent sheet, once the user has answered), so the window
    /// can re-render immediately instead of waiting for the next poll.
    static func perform(_ fix: Fix, completion: @escaping (Outcome) -> Void) {
        switch fix {
        case .none:
            completion(.done)

        case .openURL(let url, _):
            NSWorkspace.shared.open(url)
            completion(.done)

        case .copyCommand(let command, _):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(command, forType: .string)
            completion(.done)

        case .openIterm:
            openIterm()
            completion(.done)

        case .grantAutomation:
            // Blocks until the user answers the system sheet, so it cannot run
            // on the main thread — the window would freeze behind its own dialog.
            DispatchQueue.global(qos: .userInitiated).async {
                let status = AutomationPermission.check(askUserIfNeeded: true)
                DispatchQueue.main.async {
                    completion(status == OSStatus(errAEEventNotPermitted) ? .automationDenied : .done)
                }
            }

        case .openPrivacySettings:
            openPrivacySettings()
            completion(.done)

        case .installHook:
            // Same path as the menu's Install Hook, so there is one installer.
            do { try HookInstaller().install() }
            catch { NSLog("Setup: hook install failed: \(error)") }
            completion(.done)
        }
    }

    /// Bring iTerm2 to the front. There is no deep link into its preference
    /// panes, so the row's copy names the exact path and this just gets the user
    /// there. Also the cure for an undeterminable row: once iTerm2 runs, the
    /// Automation query can be answered and the API socket becomes observable.
    private static func openIterm() {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: DependencyReport.itermBundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func openPrivacySettings() {
        let automationPane = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )!
        guard !NSWorkspace.shared.open(automationPane) else { return }
        // Pane identifiers have been renamed across macOS releases; landing the
        // user in System Settings at all beats doing nothing.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
    }
}
