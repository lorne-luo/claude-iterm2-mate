import AppKit
import SwiftUI

/// The Setup checklist window — the app's only real `NSWindow`.
///
/// Deliberately not built with `PanelFactory`: that is the recipe for borderless
/// floating overlays, and this one wants a title bar and a close button.
/// One instance for the life of the app (D12), so reopening it never stacks
/// duplicates and never loses its position.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    static let shared = SetupWindowController()

    private var window: NSWindow?
    private var host: FirstMouseHostingView<SetupView>?
    private var poll: Timer?
    /// Centering waits for the first content-sized layout (see `showAtLaunch`).
    private var hasBeenPositioned = false
    /// Set once macOS has told us it will not put the Automation consent sheet
    /// up again (the user answered "Don't Allow"). From then on the only honest
    /// button is the one that opens System Settings.
    private var automationAskExhausted = false

    private override init() { super.init() }

    /// Launch presentation: visible, but it must NOT take focus. The whole app
    /// is built around never interrupting what the user is typing into a
    /// terminal, and an app that steals the keyboard while announcing itself as
    /// a good citizen is the worst possible first impression.
    ///
    /// The window is therefore ordered front without activating, which also
    /// means it is not key — hence `FirstMouseHostingView`, so the first click
    /// on a button is the click that presses it.
    ///
    /// `reload()` runs *before* the window is placed: it is what gives the window
    /// its real height, and `resizeToFit` grows downward from a fixed title bar,
    /// so centering a placeholder first would leave the finished window sitting
    /// low — its bottom rows off-screen on a short display.
    func showAtLaunch() {
        let window = ensureWindow()
        reload()
        centerOnFirstShow(window)
        window.orderFrontRegardless()
        startPolling()
    }

    /// Opened from the menu: the user asked for it, so taking focus is correct.
    func showFromMenu() {
        let window = ensureWindow()
        reload()
        centerOnFirstShow(window)
        // An .accessory app has to activate explicitly to come to the front.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startPolling()
    }

    // MARK: - Window

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let host = FirstMouseHostingView(rootView: view(rows: []))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SetupView.width, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude iTerm2 Mate Setup"
        window.contentView = host
        window.isReleasedWhenClosed = false
        // Same behavior the overlay panels get: the target user very likely has
        // iTerm2 full-screen on its own Space, and a plain window is pinned to
        // the Space it was created on — combined with a non-activating
        // `orderFrontRegardless` it would simply never be seen.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.delegate = self
        self.window = window
        self.host = host
        return window
    }

    /// Centered the first time it is shown, and never moved again (D12) — a
    /// window that jumps back to the middle every time it is reopened is worse
    /// than one the user has parked somewhere.
    private func centerOnFirstShow(_ window: NSWindow) {
        guard !hasBeenPositioned else { return }
        hasBeenPositioned = true
        window.center()
    }

    /// Re-run every probe and rebuild the rows. Shared by the Recheck button,
    /// the poll, and every fix action.
    private func reload() {
        guard let window, let host else { return }
        let rows = SetupRow.rows(
            report: DependencyReport.current(),
            hookInstalled: HookStatus.current() == .installed
        )
        // Swap the hosted view, never the host: rebuilding it would throw away
        // SwiftUI's state (and the poll rebuilds this every 2 s).
        host.rootView = view(rows: rows.map(reroutedIfAskExhausted))
        resizeToFit(window: window, host: host)
    }

    /// macOS only shows the Automation sheet once. After a refusal, offering
    /// Grant… again is a button that provably does nothing.
    private func reroutedIfAskExhausted(_ row: SetupRow) -> SetupRow {
        guard automationAskExhausted, row.fix == .grantAutomation else { return row }
        return SetupRow(
            kind: row.kind,
            state: row.state,
            title: row.title,
            subtitle: row.subtitle + " macOS will not ask again — turn it on in System Settings.",
            fix: .openPrivacySettings
        )
    }

    private func view(rows: [SetupRow]) -> SetupView {
        SetupView(
            rows: rows,
            suppressAtLaunch: AppSettings.suppressSetupAtLaunch,
            onFix: { [weak self] row in self?.perform(row) },
            onRecheck: { [weak self] in self?.reload() },
            onSuppressChanged: { [weak self] suppress in
                AppSettings.suppressSetupAtLaunch = suppress
                self?.reload()
            }
        )
    }

    private func perform(_ row: SetupRow) {
        SetupFix.perform(row.fix) { [weak self] outcome in
            if outcome == .automationDenied { self?.automationAskExhausted = true }
            // Re-render immediately rather than waiting up to 2 s: an installed
            // hook or a granted permission should turn green as the sheet closes.
            self?.reload()
        }
    }

    /// Follow the content's height. The origin is recomputed from `maxY` so the
    /// title bar stays put — an `NSWindow` grows upward from its bottom-left, so
    /// a row appearing would otherwise shove the whole window up the screen.
    private func resizeToFit(window: NSWindow, host: NSView) {
        host.layoutSubtreeIfNeeded()
        let content = NSSize(width: SetupView.width, height: host.fittingSize.height)
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
        guard abs(target.height - window.frame.height) > 0.5
            || abs(target.width - window.frame.width) > 0.5
        else { return }
        window.setFrame(
            NSRect(
                x: window.frame.minX,
                y: window.frame.maxY - target.height,
                width: target.width,
                height: target.height
            ),
            display: true
        )
    }

    // MARK: - Live recheck (D7)

    /// The launch path never activates the app, so `didBecomeActive` never
    /// fires and the promise of "tick the box in iTerm2 and watch it turn green"
    /// would need a Recheck click. Poll instead — one preferences read, a few
    /// `isExecutableFile` stats, one Apple Event and a small JSON file, and only
    /// while the window is actually on screen.
    private func startPolling() {
        guard poll == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        // .common, so the poll survives menu tracking and window drags.
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
    }
}
