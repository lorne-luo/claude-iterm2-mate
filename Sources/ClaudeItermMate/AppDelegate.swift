import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ReminderStore()
    private let usage = UsageService()
    private(set) var coordinator: ReminderCoordinator!
    private var server: NotifyServer?
    private var tabStrip: TabStripPanel?
    private lazy var detail = DetailPanel(usage: usage)
    private var menuBar: MenuBarController?

    // The four iTerm2 actions are built at the point of use, never stored.
    // Each one resolves `it2` and its interpreter in `init`, so a stored copy
    // freezes that answer at launch: a user who installs `it2` while the app is
    // running would see the menu warning clear (DependencyReport re-resolves)
    // while every click, pane color and answer stayed dead. They are cheap
    // structs — a few `isExecutableFile` stats and one 512-byte read — and the
    // work they gate always spawns a Process anyway.
    private var focusAction: ItermFocusAction { ItermFocusAction() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = ReminderCoordinator(store: store, toastPanel: ToastPanel(usage: usage), usage: usage)
        Self.configureReminderSettings(on: coordinator)
        coordinator.onActivate = { [weak self] item in self?.activate(item) }
        coordinator.isNonItermEnabled = { AppSettings.showNonIterm }
        coordinator.onNotify = { [weak self] title, subtitle, body in
            self?.desktopNotify(title: title, subtitle: subtitle, body: body)
        }
        coordinator.isPaneColoringEnabled = { AppSettings.colorPanes }
        coordinator.onSetPaneBackground = { sessionUUID, hex in
            // Fire-and-forget off the main thread. No delay needed: the Python
            // API sets the pane's background at the app layer regardless of TUI
            // state (unlike the old /color keystroke injection). Gating/dedup are
            // handled in the coordinator before this runs.
            // Built inside the block, not captured: a captured struct would pin
            // launch-time `it2` resolution for the life of the app.
            DispatchQueue.global(qos: .utility).async {
                ItermBgColorAction().apply(sessionUUID: sessionUUID, hex: hex)
            }
        }
        coordinator.onResetPaneBackground = { sessionUUID in
            // Claude Code exited; hand the pane back to its profile default.
            // Same off-main fire-and-forget shape as the apply path — and built
            // inside the block for the same reason.
            DispatchQueue.global(qos: .utility).async {
                ItermBgColorAction().reset(sessionUUID: sessionUUID)
            }
        }
        coordinator.onInjectColor = { sessionUUID, name in
            // Fire-and-forget off the main thread. Only reached on a genuine Stop
            // event (gated on `isStop` in the coordinator), so the composer is an
            // ordinary, stashable prompt — never a live permission/question TUI.
            DispatchQueue.global(qos: .utility).async {
                ItermColorAction().inject(sessionUUID: sessionUUID, colorName: name)
            }
        }
        // Any payload arriving proves the hook → socket path works end to end.
        // Guarded: this fires on EVERY payload, and a permission storm would
        // otherwise rewrite the same `true` dozens of times. It is a one-way latch.
        coordinator.onDidReceiveEvent = {
            if !AppSettings.hasReceivedEvent { AppSettings.hasReceivedEvent = true }
        }
        // Evaluated per menu open / icon refresh, so installing a missing
        // dependency clears the warning without restarting the app.
        menuBar = MenuBarController(
            report: { DependencyReport.current() },
            playSound: { [weak self] in self?.coordinator.onPlaySound?() }
        )
        tabStrip = TabStripPanel(
            store: store,
            onClick: { [weak self] item in self?.activate(item) },
            onHover: { [weak self] item, tabFrame in
                self?.detail.hoverChanged(item: item, tabFrame: tabFrame)
            },
            onClearAll: { [weak self] in self?.store.removeAll() }
        )
        detail.onClose = { [weak self] item in self?.store.remove(sessionUUID: item.sessionUUID) }
        // Answer an AskUserQuestion by injecting keystrokes into the owning pane
        // (off-main). Optimistically remove the tab; the PostToolUse `resolve`
        // hook also clears it once the answer lands.
        // One implementation shared by the detail popup and the toast, so
        // answering/chatting behaves identically from either surface.
        // A failed injection (it2 exits non-zero — most often the Python API
        // failing to resolve a live session) must not be silent: the tab is
        // already gone, so without this the answer just vanishes.
        let answerHandler: (ReminderItem, ItermSendTextAction.Answer, Int) -> Void = { [weak self] item, answer, optionCount in
            DispatchQueue.global(qos: .userInitiated).async {
                let sent = ItermSendTextAction()
                    .answer(sessionUUID: item.sessionUUID, answer: answer, optionCount: optionCount)
                guard !sent else { return }
                DispatchQueue.main.async {
                    self?.desktopNotify(
                        title: "Answer not delivered",
                        subtitle: item.projectName,
                        body: "iTerm2 rejected the keystrokes — answer in the pane instead."
                    )
                }
            }
            self?.store.remove(sessionUUID: item.sessionUUID)
        }
        // Jump to and maximize the pane, then drop the tab. Shared by two
        // triggers with identical behavior: "Chat about this" on a question card,
        // and a double-click on any title row.
        let jumpMaximizedHandler: (ReminderItem) -> Void = { [weak self] item in
            self?.focusAction.focus(sessionUUID: item.sessionUUID, maximize: true)
            self?.store.remove(sessionUUID: item.sessionUUID)
        }
        // A quick reply is typed into the composer and submitted, then the
        // reminder is consumed — the session is about to produce a new one.
        let quickReplyHandler: (ReminderItem, QuickReply) -> Void = { [weak self] item, reply in
            DispatchQueue.global(qos: .userInitiated).async {
                let sent = ItermSendTextAction()
                    .submit(sessionUUID: item.sessionUUID, text: reply.text)
                guard !sent else { return }
                DispatchQueue.main.async {
                    self?.desktopNotify(
                        title: "Quick reply not delivered",
                        subtitle: item.projectName,
                        body: "iTerm2 rejected the keystrokes — type it in the pane instead."
                    )
                }
            }
            self?.store.remove(sessionUUID: item.sessionUUID)
        }
        detail.onAnswer = answerHandler
        detail.onChat = jumpMaximizedHandler
        detail.onQuickReply = quickReplyHandler
        coordinator.onAnswer = answerHandler
        coordinator.onChat = jumpMaximizedHandler
        coordinator.onQuickReply = quickReplyHandler
        // Double-clicking a title row (toast or hover popup) is the same jump:
        // always maximized, whatever the maximize-on-click toggle says.
        detail.onJumpMaximized = jumpMaximizedHandler
        coordinator.onJumpMaximized = jumpMaximizedHandler
        // MUST run before the server starts, and synchronously. The server
        // accepts payloads the instant it is up; a `session_start` arriving
        // before the scripts are on disk finds `ItermBgColorAction.available`
        // false, and `colorPaneIfNeeded` has already recorded the hex in
        // `coloredSessions` before firing — so that pane is marked done and is
        // never retried for the life of the process. Two ~3 KB copies; the
        // main-thread cost is irrelevant next to a permanently uncolored pane.
        do { try ScriptInstaller().install() }
        catch { NSLog("Script publish on launch failed: \(error)") }

        let server = NotifyServer(socketPath: NotifyServer.defaultSocketPath) { [weak self] payload in
            self?.coordinator.handle(payload)
        }
        do {
            try server.start()
            self.server = server
        } catch NotifyServer.StartError.alreadyRunning {
            NSApp.terminate(nil)
        } catch {
            NSLog("NotifyServer failed to start: \(error)")
            menuBar?.showServerError("\(error)")
        }

        // Keep installed hooks/scripts current across app upgrades. Only when the
        // user has already opted in (hook installed): re-run the idempotent
        // installer so newly bundled hooks (e.g. the Notification hook) and the
        // latest scripts propagate without a manual remove+reinstall. Never
        // auto-installs for a user who has not opted in. Off-main: small file IO.
        if HookStatus.current() == .installed {
            DispatchQueue.global(qos: .utility).async {
                do { try HookInstaller().install() }
                catch { NSLog("Hook refresh on launch failed: \(error)") }
            }
        }

        // Say what is missing instead of looking healthy while doing nothing:
        // the Setup checklist when something blocking is unmet (or the hook is
        // not installed), the summary toast when it is only degraded, nothing
        // when everything is satisfied. See LaunchPresentation.decide.
        menuBar?.showDependencyToastIfNeeded()
    }

    static func configureReminderSettings(
        on coordinator: ReminderCoordinator,
        playSound: @escaping () -> Void = { NSSound.beep() }
    ) {
        coordinator.isTabStripEnabled = { AppSettings.showTabStrip }
        coordinator.isSoundEnabled = { AppSettings.playSound }
        coordinator.onPlaySound = playSound
    }

    /// Jump to the pane owning a reminder and consume it. Shared by tab clicks
    /// and toast clicks. Non-focusable (non-iTerm2) reminders have no pane to
    /// jump to, so clicking merely dismisses them.
    private func activate(_ item: ReminderItem) {
        if item.focusable {
            focusAction.focus(sessionUUID: item.sessionUUID, maximize: ItermFocusAction.maximizeOnClick)
        }
        store.remove(sessionUUID: item.sessionUUID)
    }

    /// Desktop notification for a non-iTerm2 session (no pane to jump to).
    /// AppleScript strings take no backslash escapes: drop backslashes, swap
    /// double quotes for curly quotes, and flatten newlines to keep the single
    /// `-e` line valid. An empty subtitle/body segment is omitted.
    private func desktopNotify(title: String, subtitle: String, body: String) {
        func sanitize(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "")
                .replacingOccurrences(of: "\"", with: "“")
                .replacingOccurrences(of: "\n", with: " ")
        }
        var script = "display notification \"\(sanitize(body))\" with title \"\(sanitize(title))\""
        let sub = sanitize(subtitle)
        if !sub.isEmpty { script += " subtitle \"\(sub)\"" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }
}
