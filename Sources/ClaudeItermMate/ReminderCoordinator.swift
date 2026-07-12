import AppKit
import Foundation

/// Owns the toast timer and the toasting→queued phase transition.
/// The store stays timer-free and fully synchronous for testability.
@MainActor
final class ReminderCoordinator {
    let store: ReminderStore
    var isPaused = false

    private let toastDuration: TimeInterval
    private let toastPanel: ToastPanelProtocol?

    init(store: ReminderStore, toastDuration: TimeInterval = 4.0, toastPanel: ToastPanelProtocol?) {
        self.store = store
        self.toastDuration = toastDuration
        self.toastPanel = toastPanel
    }

    private var visibleFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    func handle(_ p: NotifyPayload) {
        guard !isPaused else { return } // socket stays open; payload silently dropped
        let token = store.upsert(p)
        if let item = store.items.first(where: { $0.sessionUUID == p.sessionUUID }) {
            toastPanel?.show(item: item, on: visibleFrame)
        }
        let session = p.sessionUUID
        DispatchQueue.main.asyncAfter(deadline: .now() + toastDuration) { [weak self] in
            guard let self else { return }
            let wasToasting = self.store.items.contains {
                $0.sessionUUID == session && $0.phase == .toasting(token: token)
            }
            self.store.queueIfCurrent(sessionUUID: session, token: token)
            if wasToasting { self.toastPanel?.hide() }
        }
    }
}
