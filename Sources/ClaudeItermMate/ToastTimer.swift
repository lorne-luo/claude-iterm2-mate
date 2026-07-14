import Foundation

/// A pausable one-shot countdown. Hovering a toast pauses it (the user is
/// reading); leaving resumes from the remaining time, not a fresh full term.
/// Fires `onFire` once on the main queue when the remaining time elapses.
@MainActor
final class ToastTimer {
    private let onFire: () -> Void
    private var remaining: TimeInterval
    private var work: DispatchWorkItem?
    /// When the current run was (re)started; nil while paused or before start.
    private var startedAt: DispatchTime?

    init(duration: TimeInterval, onFire: @escaping () -> Void) {
        self.remaining = max(0, duration)
        self.onFire = onFire
    }

    func start() { schedule() }

    /// Freeze the countdown, banking the time already elapsed this run.
    func pause() {
        guard let startedAt else { return } // already paused / not running
        work?.cancel()
        work = nil
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000_000
        remaining = max(0, remaining - elapsed)
        self.startedAt = nil
    }

    /// Continue from the banked remaining time. No-op if already running.
    func resume() {
        guard startedAt == nil, work == nil else { return }
        schedule()
    }

    func cancel() {
        work?.cancel()
        work = nil
        startedAt = nil
    }

    private func schedule() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.work = nil
            self.startedAt = nil
            self.onFire()
        }
        self.work = work
        startedAt = .now()
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }
}
