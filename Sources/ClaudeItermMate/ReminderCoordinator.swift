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

    /// Owns the in-memory usage snapshot; refreshed (non-blocking) on each
    /// reminder and probed for claude-hud's cache on each session_start.
    private let usage: UsageService?

    /// Invoked when a toast is clicked — jump to the pane and consume the
    /// reminder (same as clicking its tab). Injected by AppDelegate.
    var onActivate: ((ReminderItem) -> Void)?

    /// Invoked for a session_start message with the session UUID and the
    /// project's assigned `/color` name. AppDelegate wires this to
    /// `ItermColorAction` (delayed off-main); tests observe it directly.
    var onSessionStart: ((_ sessionUUID: String, _ colorName: String) -> Void)?

    /// Whether non-iTerm2 (non-focusable) sessions should surface as tabs.
    /// When false they fall back to a desktop notification via `onNotify`.
    /// Defaults to always-on; AppDelegate wires it to `AppSettings.showNonIterm`.
    var isNonItermEnabled: () -> Bool = { true }

    /// Emit a plain desktop notification (title, body) — used for non-iTerm2
    /// sessions when `isNonItermEnabled` is off. Injected by AppDelegate.
    var onNotify: ((_ title: String, _ body: String) -> Void)?

    /// Token of the toast currently shown in the single shared panel. Only the
    /// timer that owns the visible toast may hide it, so an older session's
    /// timer can never dismiss a newer session's toast early.
    private struct Displayed { let token: UUID; let session: String; let findable: Bool }
    /// The toast currently in the shared panel, or nil when none is shown.
    private var displayed: Displayed?

    /// One pausable countdown per live toast, keyed by its token. Independent
    /// per session so an older session's toast still queues on its own schedule
    /// even after a newer one takes over the shared panel.
    private var timers: [UUID: ToastTimer] = [:]

    init(
        store: ReminderStore,
        toastDuration: TimeInterval = 8.0,
        toastPanel: ToastPanelProtocol?,
        probe: ItermSessionProbe = ItermSessionLookup(),
        usage: UsageService? = nil
    ) {
        self.store = store
        self.toastDuration = toastDuration
        self.toastPanel = toastPanel
        self.probe = probe
        self.usage = usage
    }

    private var visibleFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Probe iTerm2 off the main thread (the `it2` query takes ~0.3 s), then
    /// present on main. A reminder whose session is not findable still toasts
    /// but never becomes a tab.
    func handle(_ p: NotifyPayload) {
        if p.isSessionStart {
            // Color-injection trigger, not a reminder: assign (or look up) the
            // project's color now, then hand off to the injector.
            usage?.probeHudCache()
            let identity = ReminderIdentity(repoRoot: p.repoRoot, branch: p.branch, cwd: p.cwd)
            let name = store.assigner.colorName(for: identity.key)
            onSessionStart?(p.sessionUUID, name)
            return
        }
        usage?.refreshIfStale()
        if !p.focusable {
            // Non-iTerm2: no pane to probe/jump to. Show a dismiss-only tab when
            // the toggle is on; otherwise fall back to a desktop notification.
            if isNonItermEnabled() {
                present(p, findable: true)
            } else {
                onNotify?(p.title, p.summary)
            }
            return
        }
        let probe = self.probe
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let findable = probe.canFind(p.sessionUUID)
            DispatchQueue.main.async { [weak self] in self?.present(p, findable: findable) }
        }
    }

    private func present(_ p: NotifyPayload, findable: Bool) {
        let session = p.sessionUUID
        // R4: a session already showing a waiting state (a queued waiting tab or
        // the waiting toast currently on screen) must not re-toast on a follow-up
        // waiting event — e.g. a permission storm. Refresh the tab's content in
        // place and return; the existing toast/tab keeps its own schedule.
        if p.sessionStatus == .waiting,
           let existing = store.items.first(where: { $0.sessionUUID == session }),
           existing.status == .waiting,
           existing.phase == .queued || displayed?.session == session {
            store.refreshContent(
                sessionUUID: session,
                summary: p.summary,
                fullMessage: p.fullMessage,
                timestamp: p.timestamp
            )
            return
        }
        let token = store.upsert(p)
        let timer = ToastTimer(duration: toastDuration) { [weak self] in
            self?.complete(token: token, session: session, findable: findable)
        }
        timers[token] = timer
        if let item = store.items.first(where: { $0.sessionUUID == session }) {
            // A toast is already on screen — demote it into a tab immediately so
            // only one toast shows at a time, then present the newcomer.
            if let prev = displayed {
                complete(token: prev.token, session: prev.session, findable: prev.findable)
            }
            toastPanel?.show(
                item: item,
                on: visibleFrame,
                showsMinimize: findable,
                onClick: { [weak self] in
                    // Not findable → clicking does nothing; the toast just expires.
                    guard findable else { return }
                    self?.displayed = nil
                    self?.onActivate?(item)
                },
                onHover: { [weak self] inside in
                    // Pause the visible toast's countdown while the pointer is
                    // over it (the user is reading); resume on exit.
                    guard let self, let shown = self.displayed?.token else { return }
                    if inside { self.timers[shown]?.pause() } else { self.timers[shown]?.resume() }
                },
                onMinimize: { [weak self] in
                    // The button is only shown for findable toasts, so minimize
                    // always becomes a tab. Reuses the timer's completion path.
                    self?.complete(token: token, session: session, findable: true)
                },
                onClose: { [weak self] in
                    // Close dismisses without a tab — drop the item outright,
                    // regardless of findability.
                    self?.complete(token: token, session: session, findable: false)
                }
            )
            displayed = Displayed(token: token, session: session, findable: findable)
        }
        timer.start()
    }

    /// The end-of-toast transition, shared by the countdown timer and the
    /// minimize button: queue the tab (or drop it if unfindable), cancel the
    /// timer, and hide the panel if this toast is the one on screen.
    private func complete(token: UUID, session: String, findable: Bool) {
        timers[token]?.cancel()
        timers[token] = nil
        if findable {
            store.queueIfCurrent(sessionUUID: session, token: token)
        } else {
            // No jumpable pane: drop it instead of leaving a dead tab.
            store.removeIfCurrent(sessionUUID: session, token: token)
        }
        // Hide only if this timer's toast is still the one on screen; a newer
        // toast (any session) owns the panel and keeps its full time. Shrink
        // into the strip only when it actually became a tab (findable); a
        // dropped toast just fades so the animation never lies about a tab.
        if displayed?.token == token {
            toastPanel?.hide(intoTab: findable)
            displayed = nil
        }
    }
}
