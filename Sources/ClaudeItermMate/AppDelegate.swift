import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ReminderStore()
    private let usage = UsageService()
    private(set) var coordinator: ReminderCoordinator!
    private var server: NotifyServer?
    private var tabStrip: TabStripPanel?
    private lazy var detail = DetailPanel(usage: usage)
    private let focusAction = ItermFocusAction()
    private let bgColorAction = ItermBgColorAction()
    private let colorAction = ItermColorAction()
    private let sendTextAction = ItermSendTextAction()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = ReminderCoordinator(store: store, toastPanel: ToastPanel(usage: usage), usage: usage)
        coordinator.onActivate = { [weak self] item in self?.activate(item) }
        coordinator.isNonItermEnabled = { AppSettings.showNonIterm }
        coordinator.onNotify = { [weak self] title, subtitle, body in
            self?.desktopNotify(title: title, subtitle: subtitle, body: body)
        }
        coordinator.isPaneColoringEnabled = { AppSettings.colorPanes }
        let bgColorAction = self.bgColorAction
        coordinator.onSetPaneBackground = { sessionUUID, hex in
            // Fire-and-forget off the main thread. No delay needed: the Python
            // API sets the pane's background at the app layer regardless of TUI
            // state (unlike the old /color keystroke injection). Gating/dedup are
            // handled in the coordinator before this runs.
            DispatchQueue.global(qos: .utility).async {
                bgColorAction.apply(sessionUUID: sessionUUID, hex: hex)
            }
        }
        let colorAction = self.colorAction
        coordinator.onInjectColor = { sessionUUID, name in
            // Fire-and-forget off the main thread. Only reached on a genuine Stop
            // event (gated on `isStop` in the coordinator), so the composer is an
            // ordinary, stashable prompt — never a live permission/question TUI.
            DispatchQueue.global(qos: .utility).async {
                colorAction.inject(sessionUUID: sessionUUID, colorName: name)
            }
        }
        menuBar = MenuBarController(focusAvailable: focusAction.canFocus)
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
        let sendTextAction = self.sendTextAction
        detail.onAnswer = { [weak self] item, answer, optionCount in
            DispatchQueue.global(qos: .userInitiated).async {
                sendTextAction.answer(sessionUUID: item.sessionUUID, answer: answer, optionCount: optionCount)
            }
            self?.store.remove(sessionUUID: item.sessionUUID)
        }
        // "Chat about this": jump to and maximize the pane, then drop the tab.
        detail.onChat = { [weak self] item in
            self?.focusAction.focus(sessionUUID: item.sessionUUID, maximize: true)
            self?.store.remove(sessionUUID: item.sessionUUID)
        }
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
