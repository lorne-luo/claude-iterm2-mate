import Foundation

/// One line of the Setup checklist, fully resolved: what to show, and the single
/// button to offer.
///
/// Pure and separate from `SetupView` so "which rows, in what order, in what
/// state, with which button" is unit-testable — the SwiftUI layer is then only
/// a renderer, which is the part that cannot be tested headless anyway.
struct SetupRow: Equatable, Identifiable {
    enum Kind: Equatable, Hashable {
        case dependency(DependencyReport.Dependency)
        /// The Claude Code hook. Deliberately not a `Dependency`: it is an
        /// opt-in, not a broken prerequisite, and folding it into that enum
        /// would put it in the menu's warning rows and the launch toast, where
        /// "you have not turned this on yet" reads as a fault.
        case hook
    }

    let kind: Kind
    let state: DependencyState
    let title: String
    /// What breaks (missing), the evidence (ok), or why we cannot tell (unknown).
    let subtitle: String
    let fix: Fix

    var id: Kind { kind }

    /// Dependency rows in declaration order, then the hook row.
    static func rows(report: DependencyReport, hookInstalled: Bool) -> [SetupRow] {
        var rows = report.all.map { status in
            SetupRow(
                kind: .dependency(status.dependency),
                state: status.state,
                title: status.dependency.title,
                // `detail` covers ok/unknown; a missing row's story is its impact.
                subtitle: status.detail ?? status.dependency.impact,
                fix: fix(for: status)
            )
        }
        rows.append(hookRow(installed: hookInstalled))
        return rows
    }

    private static func fix(for status: DependencyStatus) -> Fix {
        switch status.state {
        case .ok:
            return .none
        case .missing:
            return status.dependency.fix
        case .unknown:
            // Both undeterminable cases — Automation with iTerm2 not running,
            // and a Python API preference we cannot read — are answered by
            // iTerm2 being up: it makes macOS able to reply, and it creates the
            // API socket that settles the other. The row's own fix would be
            // wrong here (Grant… cannot ask about a process that is not there).
            return .openIterm(label: "Open iTerm2")
        }
    }

    private static func hookRow(installed: Bool) -> SetupRow {
        SetupRow(
            kind: .hook,
            state: installed ? .ok : .missing,
            title: "Claude Code hook",
            subtitle: installed
                ? "Registered in ~/.claude/settings.json."
                : "Claude Code is not telling the app anything — no toasts, no tabs, no pane coloring.",
            fix: installed ? .none : .installHook
        )
    }
}
