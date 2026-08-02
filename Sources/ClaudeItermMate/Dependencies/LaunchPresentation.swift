import Foundation

/// What, if anything, to put in front of the user at launch.
///
/// Pulled out of `MenuBarController` as a pure function so the escalation rules
/// are unit-testable: the alternative is a manual matrix of app restarts under
/// hand-broken dependencies.
enum LaunchPresentation {
    enum Action: Equatable {
        /// The checklist window, unmissable but non-activating (D6).
        case setupWindow
        /// The existing non-interactive summary toast.
        case infoToast
        case none
    }

    /// Escalation, in order:
    /// - the app cannot do its job (something blocking is broken, or the hook is
    ///   not installed at all) → the window, unless the user opted out of it;
    /// - something is degraded, or the user opted out → the toast;
    /// - otherwise nothing.
    ///
    /// A missing hook counts even though it is not a `Dependency`: it is "not
    /// opted in" rather than "broken", so it must not pollute the warning rows —
    /// but the window is where the Install button lives, so it has to open.
    ///
    /// `.unknown` rows reach neither branch: they are in neither `hasBlocking`
    /// nor `hasAnyMissing`, so nothing we merely failed to observe can interrupt.
    static func decide(
        report: DependencyReport,
        hookInstalled: Bool,
        suppressed: Bool
    ) -> Action {
        if (report.hasBlocking || !hookInstalled) && !suppressed { return .setupWindow }
        if report.hasAnyMissing { return .infoToast }
        return .none
    }
}
