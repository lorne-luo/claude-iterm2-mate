import AppKit
import Foundation

/// Owns the toast timer and the toasting→queued phase transition.
/// The store stays timer-free and fully synchronous for testability.
@MainActor
final class ReminderCoordinator {
    let store: ReminderStore

    private let toastDuration: TimeInterval
    private let toastPanel: ToastPanelProtocol?
    private let probe: ItermSessionProbe

    /// Invoked when a toast is clicked — jump to the pane and consume the
    /// reminder (same as clicking its tab). Injected by AppDelegate.
    var onActivate: ((ReminderItem) -> Void)?

    /// Token of the toast currently shown in the single shared panel. Only the
    /// timer that owns the visible toast may hide it, so an older session's
    /// timer can never dismiss a newer session's toast early.
    private var displayedToken: UUID?

    /// One pausable countdown per live toast, keyed by its token. Independent
    /// per session so an older session's toast still queues on its own schedule
    /// even after a newer one takes over the shared panel.
    private var timers: [UUID: ToastTimer] = [:]

    init(
        store: ReminderStore,
        toastDuration: TimeInterval = 8.0,
        toastPanel: ToastPanelProtocol?,
        probe: ItermSessionProbe = ItermSessionLookup()
    ) {
        self.store = store
        self.toastDuration = toastDuration
        self.toastPanel = toastPanel
        self.probe = probe
    }

    private var visibleFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Probe iTerm2 off the main thread (the `it2` query takes ~0.3 s), then
    /// present on main. A reminder whose session is not findable still toasts
    /// but never becomes a tab.
    func handle(_ p: NotifyPayload) {
        let probe = self.probe
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let findable = probe.canFind(p.sessionUUID)
            DispatchQueue.main.async { self?.present(p, findable: findable) }
        }
    }

    private func present(_ p: NotifyPayload, findable: Bool) {
        let token = store.upsert(p)
        let session = p.sessionUUID
        let timer = ToastTimer(duration: toastDuration) { [weak self] in
            guard let self else { return }
            self.timers[token] = nil
            if findable {
                self.store.queueIfCurrent(sessionUUID: session, token: token)
            } else {
                // No jumpable pane: drop it instead of leaving a dead tab.
                self.store.removeIfCurrent(sessionUUID: session, token: token)
            }
            // Hide only if this timer's toast is still the one on screen; a
            // newer toast (any session) owns the panel and keeps its full time.
            if self.displayedToken == token {
                self.toastPanel?.hide()
                self.displayedToken = nil
            }
        }
        timers[token] = timer
        if let item = store.items.first(where: { $0.sessionUUID == session }) {
            // The outgoing toast is no longer readable — resume its (possibly
            // hover-paused) timer so it still queues on schedule.
            if let prev = displayedToken { timers[prev]?.resume() }
            toastPanel?.show(
                item: item,
                on: visibleFrame,
                onClick: { [weak self] in
                    // Not findable → clicking does nothing; the toast just expires.
                    guard findable else { return }
                    self?.displayedToken = nil
                    self?.onActivate?(item)
                },
                onHover: { [weak self] inside in
                    // Pause the visible toast's countdown while the pointer is
                    // over it (the user is reading); resume on exit.
                    guard let self, let shown = self.displayedToken else { return }
                    if inside { self.timers[shown]?.pause() } else { self.timers[shown]?.resume() }
                }
            )
            displayedToken = token
        }
        timer.start()
    }
}
