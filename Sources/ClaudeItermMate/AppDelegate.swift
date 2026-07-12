import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ReminderStore()
    private(set) var coordinator: ReminderCoordinator!
    private var server: NotifyServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = ReminderCoordinator(store: store, toastPanel: ToastPanel())
        let server = NotifyServer(socketPath: NotifyServer.defaultSocketPath) { [weak self] payload in
            self?.coordinator.handle(payload)
        }
        do {
            try server.start()
            self.server = server
        } catch NotifyServer.StartError.alreadyRunning {
            NSApp.terminate(nil) // single-instance guard
        } catch {
            NSLog("NotifyServer failed to start: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }
}
