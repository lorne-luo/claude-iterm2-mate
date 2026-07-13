import AppKit
import Foundation

/// Owns the toast timer and the toasting→queued phase transition.
/// The store stays timer-free and fully synchronous for testability.
@MainActor
final class ReminderCoordinator {
    let store: ReminderStore

    private let toastDuration: TimeInterval
    private let toastPanel: ToastPanelProtocol?

    /// Token of the toast currently shown in the single shared panel. Only the
    /// timer that owns the visible toast may hide it, so an older session's
    /// timer can never dismiss a newer session's toast early.
    private var displayedToken: UUID?

    init(store: ReminderStore, toastDuration: TimeInterval = 4.0, toastPanel: ToastPanelProtocol?) {
        self.store = store
        self.toastDuration = toastDuration
        self.toastPanel = toastPanel
    }

    private var visibleFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    func handle(_ p: NotifyPayload) {
        let token = store.upsert(p)
        if let item = store.items.first(where: { $0.sessionUUID == p.sessionUUID }) {
            toastPanel?.show(item: item, on: visibleFrame)
            displayedToken = token
        }
        let session = p.sessionUUID
        DispatchQueue.main.asyncAfter(deadline: .now() + toastDuration) { [weak self] in
            guard let self else { return }
            self.store.queueIfCurrent(sessionUUID: session, token: token)
            // Hide only if this timer's toast is still the one on screen; a
            // newer toast (any session) owns the panel and keeps its full time.
            if self.displayedToken == token {
                self.toastPanel?.hide()
                self.displayedToken = nil
            }
        }
    }
}
