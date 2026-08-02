import AppKit
import Foundation

/// Three-valued, because "we could not check" is a real answer and must not be
/// laundered into either of the other two. Automation cannot be determined
/// while iTerm2 is not running (see `AutomationPermission`), which is exactly
/// the state of a login-item launch or a fresh install — calling that `.ok`
/// hides the most confusing failure the app has, and calling it `.missing`
/// cries wolf at every boot.
enum DependencyState: Equatable {
    case ok
    case missing
    case unknown
}

/// How badly a missing dependency hurts. Only `blocking` opens the Setup window
/// at launch; `degraded` is listed but never interrupts.
enum Severity: Equatable {
    case blocking
    case degraded
}

/// One row of the checklist: which prerequisite, what we found, and the
/// supporting text for the two states where the row has something extra to say.
struct DependencyStatus: Equatable {
    let dependency: DependencyReport.Dependency
    let state: DependencyState
    /// `.ok` → the evidence; `.unknown` → why we could not tell; `.missing` →
    /// nil, because the row's subtitle is then its `impact` (what breaks).
    let detail: String?
}

/// Which of the app's external prerequisites are unmet, so the menu bar, the
/// launch toast and the Setup window can say so instead of looking healthy
/// while doing nothing.
///
/// `evaluate` is pure (every input injected) and holds all the logic; `current()`
/// is the only part that touches the real system.
struct DependencyReport {
    /// iTerm2's bundle id (verified: `osascript -e 'id of application "iTerm2"'`).
    static let itermBundleID = "com.googlecode.iterm2"

    /// Declaration order is presentation order — the menu rows, the toast lines
    /// and the Setup rows all read it straight through.
    enum Dependency: CaseIterable {
        /// iTerm2 itself is not installed — the app degrades to a desktop notifier.
        case iterm2
        /// The `it2` CLI is missing, which also means no `iterm2`-capable Python.
        case it2
        /// `uv` is how `it2` gets installed. Only reported when `it2` is broken.
        case uv
        /// iTerm2's Python API is switched off. The `it2` binary can be perfectly
        /// installed and every it2-powered action still fails (see CLAUDE.md's
        /// "`it2` on disk ≠ able to reach iTerm2").
        case pythonAPI
        /// Apple Events (Automation) consent for controlling iTerm2, which the
        /// AppleScript session enumeration needs.
        case automation
        /// The hook is installed but no payload has ever arrived (see D2: we detect
        /// the symptom, never probe `node` — a GUI app has only launchd's PATH).
        case delivery

        var severity: Severity {
            switch self {
            case .iterm2, .it2, .pythonAPI, .automation:
                return .blocking
            // `uv` alone breaks nothing that is not already broken by `it2`, and
            // `delivery` is false by construction for anyone who just installed
            // the hook and has not finished a Claude turn yet.
            case .uv, .delivery:
                return .degraded
            }
        }

        /// Setup window row title.
        var title: String {
            switch self {
            case .iterm2: return "iTerm2"
            case .it2: return "it2 CLI"
            case .uv: return "uv"
            case .pythonAPI: return "iTerm2 Python API"
            case .automation: return "Automation permission"
            case .delivery: return "Hook event delivery"
            }
        }

        /// What stops working while this is unmet — the Setup row's subtitle.
        var impact: String {
            switch self {
            case .iterm2:
                return "No panes to jump to; reminders fall back to desktop notifications. Get it at iterm2.com."
            case .it2:
                return "No jump, pane color, /color, or question answers."
            case .uv:
                return "uv installs it2. Without it you cannot repair the it2 install."
            case .pythonAPI:
                return "Disabled: every it2-powered action fails silently — jump, pane color, /color, question answers. Turn on Enable Python API in iTerm2 Settings › General › Magic."
            case .automation:
                return "iTerm2 sessions cannot be enumerated, so reminders only toast and never become tabs, and closed panes are never cleaned up."
            case .delivery:
                return "The hook is registered but nothing has arrived. Check that node is on Claude Code's PATH, then restart Claude Code."
            }
        }

        /// Shown when the row is satisfied. A green checklist that says nothing
        /// is unfalsifiable — the user cannot tell a real pass from a stub.
        var okDetail: String {
            switch self {
            case .iterm2: return "Installed (found via LaunchServices)."
            case .it2: return "it2 and its iterm2-capable Python both resolve."
            case .uv: return "Installed."
            case .pythonAPI: return "Enabled."
            case .automation: return "This app may control iTerm2."
            case .delivery: return "At least one hook event has reached the app."
            }
        }

        /// Shown when the row is `.unknown`: what the user must change before a
        /// Recheck can produce a real answer.
        var unknownReason: String {
            switch self {
            case .automation:
                return "iTerm2 is not running, so macOS cannot answer. Start iTerm2 — this row updates on its own."
            case .pythonAPI:
                // Deliberately does not name a cause: the probe answers .unknown
                // for a custom preferences folder *and* for a value it cannot
                // read as a boolean, and asserting the wrong one is exactly the
                // confidently-wrong UI this checklist exists to replace.
                return "iTerm2's preference file could not be read. Check Enable Python API in iTerm2 Settings › General › Magic."
            // The remaining probes are plain yes/no and never return .unknown;
            // this only keeps the row from rendering an empty subtitle.
            case .iterm2, .it2, .uv, .delivery:
                return "Could not be determined."
            }
        }

        /// The single action the Setup window offers for this row.
        var fix: Fix {
            switch self {
            case .iterm2:
                return .openURL(URL(string: "https://iterm2.com")!, label: "Download iTerm2")
            case .it2:
                return .copyCommand(command: "uv tool install it2", label: "Copy: uv tool install it2")
            case .uv:
                return .copyCommand(
                    command: "curl -LsSf https://astral.sh/uv/install.sh | sh",
                    label: "Copy install command"
                )
            case .pythonAPI:
                // No deep link exists into that preference pane, and writing the
                // plist ourselves would be reverted when iTerm2 quits — so all we
                // can do is put iTerm2 in front of the user.
                return .openIterm(label: "Open iTerm2")
            case .automation:
                return .grantAutomation
            case .delivery:
                return .copyCommand(command: "which node", label: "Copy: which node")
            }
        }

        /// One disabled menu row, with the fix inline.
        var menuTitle: String {
            switch self {
            case .iterm2:
                return "iTerm2 not installed — download it from iterm2.com"
            case .it2:
                return "it2 not found — no jump, pane color, /color, question answers. Run: uv tool install it2"
            case .uv:
                return "uv not found — it installs it2. Run: curl -LsSf https://astral.sh/uv/install.sh | sh"
            case .pythonAPI:
                return "iTerm2 Python API off — jump, pane color, /color and answers all fail. iTerm2 › Settings › General › Magic › Enable Python API"
            case .automation:
                return "Automation permission missing — reminders never become tabs. System Settings › Privacy & Security › Automation"
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
            case .uv:
                return "• uv missing — it is how it2 gets installed. See astral.sh/uv"
            case .pythonAPI:
                return "• iTerm2 Python API off — every it2 action fails. iTerm2 › Settings › General › Magic › Enable Python API"
            case .automation:
                return "• Automation permission missing — reminders never become tabs. Grant it in System Settings › Privacy & Security"
            case .delivery:
                return "• No hook events received yet — check that node is on Claude Code's PATH, then restart it."
            }
        }
    }

    /// Every row we actually evaluated, in declaration order — including the
    /// satisfied and the undeterminable ones, which is what the Setup window
    /// renders. Rows that make no sense in the current world (the Python API
    /// with no iTerm2 installed) are absent rather than faked.
    let all: [DependencyStatus]

    /// Unchanged semantics for the existing menu rows and launch toast: only
    /// things we positively observed to be broken. `.unknown` never lands here.
    var missing: [Dependency] {
        all.filter { $0.state == .missing }.map(\.dependency)
    }

    /// The subset that justifies interrupting the user at launch.
    var blocking: [Dependency] {
        missing.filter { $0.severity == .blocking }
    }

    var hasAnyMissing: Bool { !missing.isEmpty }
    var hasBlocking: Bool { !blocking.isEmpty }

    /// The pure core. Two rules run through all of it:
    /// - a row that cannot mean anything yet is *omitted*, not reported (the
    ///   Python API without iTerm2, `uv` with a working `it2`, delivery before
    ///   the user has opted in) — reporting it would bury the fix that matters;
    /// - a row we could not check is `.unknown`, which is listed but never
    ///   counted as missing.
    static func evaluate(
        itermInstalled: Bool,
        it2Usable: Bool,
        uvInstalled: Bool,
        pythonAPI: DependencyState,
        automation: DependencyState,
        hookInstalled: Bool,
        hasReceivedEvent: Bool
    ) -> DependencyReport {
        var all: [DependencyStatus] = [
            status(.iterm2, itermInstalled ? .ok : .missing),
            status(.it2, it2Usable ? .ok : .missing),
        ]
        // Only meaningful as "how do I install it2" — noise once it2 works.
        if !it2Usable {
            all.append(status(.uv, uvInstalled ? .ok : .missing))
        }
        if itermInstalled {
            all.append(status(.pythonAPI, pythonAPI))
            all.append(status(.automation, automation))
        }
        // Hook absent is "not opted in", not "broken".
        if hookInstalled {
            all.append(status(.delivery, hasReceivedEvent ? .ok : .missing))
        }
        return DependencyReport(all: all)
    }

    private static func status(_ dependency: Dependency, _ state: DependencyState) -> DependencyStatus {
        let detail: String?
        switch state {
        case .ok: detail = dependency.okDetail
        case .unknown: detail = dependency.unknownReason
        // Left to the row's `impact`, so the "what breaks" copy has one home.
        case .missing: detail = nil
        }
        return DependencyStatus(dependency: dependency, state: state, detail: detail)
    }

    /// Evaluate against the live system. `NSWorkspace` answers "installed?" with
    /// no subprocess — `ItermSessionLookup` cannot, since its `is running` guard
    /// yields an empty Set for both "not installed" and "no panes open".
    ///
    /// Cheap enough for the Setup window's 2 s poll: a preferences read, a few
    /// `isExecutableFile` stats, one Apple Event IPC and a small JSON file.
    static func current() -> DependencyReport {
        // `it2` counts as usable only when its interpreter also resolves. The
        // binary alone is a proxy, not a capability: an `it2` whose launcher is
        // not a shebang-python script leaves pane coloring and maximize-on-click
        // silently dead while the menu claims everything is fine — exactly the
        // failure this type exists to prevent. `uv tool install it2` is still the
        // right advice, since reinstalling repairs a broken venv too.
        let it2URL = ItermFocusAction.resolveIt2()
        let itermInstalled = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: itermBundleID) != nil
        return evaluate(
            itermInstalled: itermInstalled,
            it2Usable: it2URL != nil && PythonInterpreter.resolve(it2URL: it2URL) != nil,
            uvInstalled: UvLocator.resolve() != nil,
            // Skipped entirely without iTerm2: `evaluate` drops both rows anyway,
            // and the Apple Event round trip is the one costly probe here.
            pythonAPI: itermInstalled ? ItermPythonAPIProbe.current() : .unknown,
            automation: itermInstalled
                // Silent query: never pops a consent sheet on its own. The Setup
                // window's Grant… button is the only caller that asks.
                ? AutomationPermission.state(for: AutomationPermission.check(askUserIfNeeded: false))
                : .unknown,
            hookInstalled: HookStatus.current() == .installed,
            hasReceivedEvent: AppSettings.hasReceivedEvent
        )
    }
}
