import AppKit
import ServiceManagement

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let focusAvailable: Bool
    private var statusItem: NSStatusItem!
    private var serverError: String?
    private let menu = NSMenu()
    private lazy var infoToast = InfoToastPanel()

    init(focusAvailable: Bool) {
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
        )?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
    }

    /// A menu-item icon. With no color the symbol renders as a template in the
    /// standard menu text color; with a color it is palette-tinted (used for
    /// the status light and warnings).
    private func symbol(_ name: String, color: NSColor? = nil) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        guard let color else { return image }
        return image?.withSymbolConfiguration(.init(paletteColors: [color]))
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hookStatus = HookStatus.current()
        let installed = hookStatus == .installed

        if let serverError {
            let item = NSMenuItem(title: "Not receiving: \(serverError)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = symbol("exclamationmark.triangle.fill", color: .systemOrange)
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if !focusAvailable {
            let warn = NSMenuItem(
                title: "it2 not found — run: uv tool install it2",
                action: nil, keyEquivalent: ""
            )
            warn.isEnabled = false
            warn.image = symbol("exclamationmark.triangle", color: .systemYellow)
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        // Hook status: a traffic-light status line whose submenu holds the
        // action, so the light (state) and the verb (action) never conflict.
        let status = NSMenuItem(
            title: installed ? "Hook installed" : "Hook not installed",
            action: nil, keyEquivalent: ""
        )
        status.image = symbol("circle.fill", color: installed ? .systemGreen : .systemRed)
        status.isEnabled = true // required (autoenablesItems=false) so the submenu opens
        let sub = NSMenu()
        let action: NSMenuItem
        if installed {
            action = NSMenuItem(title: "Remove Hook…", action: #selector(confirmRemoveHook), keyEquivalent: "")
            action.image = symbol("trash")
        } else {
            action = NSMenuItem(title: "Install Hook", action: #selector(installHook), keyEquivalent: "")
            action.image = symbol("arrow.down.circle")
        }
        action.target = self
        action.isEnabled = true
        sub.addItem(action)
        status.submenu = sub
        menu.addItem(status)
        menu.addItem(.separator())

        let maximize = NSMenuItem(title: "Maximize Pane on Click", action: #selector(toggleMaximize(_:)), keyEquivalent: "")
        maximize.target = self
        maximize.state = ItermFocusAction.maximizeOnClick ? .on : .off
        maximize.isEnabled = installed
        maximize.image = symbol("arrow.up.left.and.arrow.down.right")
        menu.addItem(maximize)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.isEnabled = installed
        login.image = symbol("power")
        menu.addItem(login)
        let nonIterm = NSMenuItem(
            title: "Show Non-iTerm2 Sessions", action: #selector(toggleNonIterm(_:)), keyEquivalent: ""
        )
        nonIterm.target = self
        nonIterm.state = AppSettings.showNonIterm ? .on : .off
        nonIterm.isEnabled = installed
        nonIterm.image = symbol("macwindow.on.rectangle")
        menu.addItem(nonIterm)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = symbol("xmark.circle")
        menu.addItem(quit)
    }

    @objc private func installHook() {
        do {
            try HookInstaller().install()
            // Success: an in-app SwiftUI toast (not osascript) so the "ready for
            // work" confirmation matches the app's own reminder styling.
            infoToast.show(title: "Ready for work", message: "Hook installed — reminders are now active.")
        } catch {
            NSLog("Hook install failed: \(error)")
            notify("Hook install failed: \(error.localizedDescription)")
        }
        populate(menu)
    }

    @objc private func confirmRemoveHook() {
        let alert = NSAlert()
        alert.messageText = "Remove the Claude iTerm2 Mate hook?"
        alert.informativeText = "Claude Code will stop sending reminders to this app. You can re-add it any time with Install me."
        alert.alertStyle = .warning
        // Cancel is added first so it is the default (Return) button — an
        // accidental Return must not remove the hook. Remove is second and
        // does not respond to Return.
        alert.addButton(withTitle: "Cancel")
        let remove = alert.addButton(withTitle: "Remove")
        remove.keyEquivalent = ""
        // .accessory apps must activate to bring a modal alert to the front.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            try HookInstaller().uninstall()
            notify("Hook removed. Reminders are now off.")
        } catch {
            NSLog("Hook uninstall failed: \(error)")
            notify("Hook removal failed: \(error.localizedDescription)")
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

    @objc private func toggleMaximize(_ sender: NSMenuItem) {
        ItermFocusAction.maximizeOnClick.toggle()
        sender.state = ItermFocusAction.maximizeOnClick ? .on : .off
    }

    @objc private func toggleNonIterm(_ sender: NSMenuItem) {
        AppSettings.showNonIterm.toggle()
        sender.state = AppSettings.showNonIterm ? .on : .off
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
