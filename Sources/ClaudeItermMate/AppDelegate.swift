import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ReminderStore()
    private(set) var coordinator: ReminderCoordinator!
    private var server: NotifyServer?
    private var tabStrip: TabStripPanel?
    private let detail = DetailPanel()
    private let focusAction = ItermFocusAction()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = ReminderCoordinator(store: store, toastPanel: ToastPanel())
        menuBar = MenuBarController(
            store: store,
            coordinator: coordinator,
            focusAvailable: focusAction.isAvailable
        )
        tabStrip = TabStripPanel(
            store: store,
            onClick: { [weak self] item in
                guard let self else { return }
                self.focusAction.focus(sessionUUID: item.sessionUUID)
                self.store.remove(sessionUUID: item.sessionUUID)
            },
            onHover: { [weak self] item, tabFrame in
                self?.detail.hoverChanged(item: item, tabFrame: tabFrame)
            }
        )
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }
}
