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
    private let colorAction = ItermColorAction()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = ReminderCoordinator(store: store, toastPanel: ToastPanel(usage: usage), usage: usage)
        coordinator.onActivate = { [weak self] item in self?.activate(item) }
        coordinator.isNonItermEnabled = { AppSettings.showNonIterm }
        coordinator.onNotify = { [weak self] title, body in self?.desktopNotify(title: title, body: body) }
        let colorAction = self.colorAction
        coordinator.onSessionStart = { sessionUUID, colorName in
            // Delay so a freshly launched Claude Code TUI is in raw mode and
            // owns the tty before the keystrokes arrive; injection itself is
            // fire-and-forget off the main thread.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                colorAction.inject(sessionUUID: sessionUUID, colorName: colorName)
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

    /// Plain macOS desktop notification for non-iTerm2 sessions when the
    /// "show non-iTerm2 sessions" toggle is off.
    private func desktopNotify(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\"", with: "“")
        let safeBody = body.replacingOccurrences(of: "\"", with: "“")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(safeBody)\" with title \"\(safeTitle)\""]
        try? p.run()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }
}
