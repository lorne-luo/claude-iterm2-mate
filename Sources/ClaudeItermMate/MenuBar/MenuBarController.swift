import AppKit
import ServiceManagement

@MainActor
final class MenuBarController: NSObject {
    private let store: ReminderStore
    private let coordinator: ReminderCoordinator
    private let focusAvailable: Bool
    private var statusItem: NSStatusItem!
    private var serverError: String?

    init(store: ReminderStore, coordinator: ReminderCoordinator, focusAvailable: Bool) {
        self.store = store
        self.coordinator = coordinator
        self.focusAvailable = focusAvailable
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshIcon()
        statusItem.menu = buildMenu()
    }

    /// Surface a fatal server-start failure: swap the icon to a warning and
    /// pin the reason to the top of the menu. Without this the app looks
    /// healthy while silently receiving nothing.
    func showServerError(_ message: String) {
        serverError = message
        refreshIcon()
        statusItem.menu = buildMenu()
    }

    private func refreshIcon() {
        let symbol = (focusAvailable && serverError == nil) ? "bell.badge" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Claude iTerm2 Mate"
        )
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if let serverError {
            let item = NSMenuItem(title: "Not receiving: \(serverError)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if !focusAvailable {
            let warn = NSMenuItem(
                title: "it2 not found — run: uv tool install it2",
                action: nil, keyEquivalent: ""
            )
            warn.isEnabled = false
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        let pause = NSMenuItem(title: "Pause Reminders", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let clear = NSMenuItem(title: "Clear All Tabs", action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        let maximize = NSMenuItem(title: "Maximize Pane on Click", action: #selector(toggleMaximize(_:)), keyEquivalent: "")
        maximize.target = self
        maximize.state = ItermFocusAction.maximizeOnClick ? .on : .off
        menu.addItem(maximize)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        coordinator.isPaused.toggle()
        sender.state = coordinator.isPaused ? .on : .off
    }

    @objc private func clearAll() {
        store.removeAll()
    }

    @objc private func toggleMaximize(_ sender: NSMenuItem) {
        ItermFocusAction.maximizeOnClick.toggle()
        sender.state = ItermFocusAction.maximizeOnClick ? .on : .off
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        // SMAppService only works from a bundled .app; from `swift run` it throws.
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } catch {
            NSLog("Launch-at-login toggle failed (needs a bundled .app): \(error)")
        }
    }
}
