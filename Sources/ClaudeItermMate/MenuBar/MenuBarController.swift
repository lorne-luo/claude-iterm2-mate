import AppKit
import ServiceManagement

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let store: ReminderStore
    private let coordinator: ReminderCoordinator
    private let focusAvailable: Bool
    private var statusItem: NSStatusItem!
    private var serverError: String?
    private let menu = NSMenu()

    init(store: ReminderStore, coordinator: ReminderCoordinator, focusAvailable: Bool) {
        self.store = store
        self.coordinator = coordinator
        self.focusAvailable = focusAvailable
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshIcon()
        menu.delegate = self
        // We drive enablement explicitly (disabled items when the hook is not
        // installed); AppKit's auto-enabling would re-enable them by target.
        menu.autoenablesItems = false
        populate(menu)
        statusItem.menu = menu
    }

    /// Surface a fatal server-start failure: swap the icon to a warning and
    /// pin the reason to the top of the menu. Without this the app looks
    /// healthy while silently receiving nothing.
    func showServerError(_ message: String) {
        serverError = message
        refreshIcon()
        populate(menu)
    }

    /// Rebuild the menu each time it opens so the hook light reflects live
    /// settings.json state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func refreshIcon() {
        let symbol = (focusAvailable && serverError == nil) ? "bell.badge" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Claude iTerm2 Mate"
        )
    }

    private func dot(_ color: NSColor) -> NSImage? {
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        return image?.withSymbolConfiguration(.init(paletteColors: [color]))
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hookStatus = HookStatus.current()
        let installed = hookStatus == .installed

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

        // Hook status light.
        if installed {
            let active = NSMenuItem(title: "Hook active", action: nil, keyEquivalent: "")
            active.isEnabled = false
            active.image = dot(.systemGreen)
            menu.addItem(active)
        } else {
            let install = NSMenuItem(title: "Install me", action: #selector(installHook), keyEquivalent: "")
            install.target = self
            install.image = dot(.systemRed)
            menu.addItem(install)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause Reminders", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.target = self
        pause.state = coordinator.isPaused ? .on : .off
        pause.isEnabled = installed
        menu.addItem(pause)
        let clear = NSMenuItem(title: "Clear All Tabs", action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = installed
        menu.addItem(clear)
        let maximize = NSMenuItem(title: "Maximize Pane on Click", action: #selector(toggleMaximize(_:)), keyEquivalent: "")
        maximize.target = self
        maximize.state = ItermFocusAction.maximizeOnClick ? .on : .off
        maximize.isEnabled = installed
        menu.addItem(maximize)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.isEnabled = installed
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func installHook() {
        do {
            try HookInstaller().install()
            notify("Hook installed — reminders are now active.")
        } catch {
            NSLog("Hook install failed: \(error)")
            notify("Hook install failed: \(error.localizedDescription)")
        }
        populate(menu)
    }

    /// Confirm the install with a desktop notification — the menu closes on
    /// click, so this is the only immediate feedback the user sees.
    private func notify(_ message: String) {
        let safe = message.replacingOccurrences(of: "\"", with: "'")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(safe)\" with title \"Claude iTerm2 Mate\""]
        try? p.run()
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
