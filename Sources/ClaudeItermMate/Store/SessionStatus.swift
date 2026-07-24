import Foundation

/// Whether a session's tab means "finished, look when you can" or "blocked,
/// waiting for me to act". Orthogonal to `ReminderPhase` (toasting/queued):
/// a tab in either phase can be completed or waiting.
///
/// The wire value comes from the hook's optional `status` field; an absent or
/// unrecognized value maps to `.completed` so old payloads stay backward
/// compatible.
enum SessionStatus: Equatable {
    case completed
    case waiting

    /// Maps the payload's raw string (`"waiting"` / `"completed"` / nil) to a
    /// status. Anything that is not exactly `"waiting"` is `.completed`.
    init(wire: String?) {
        self = wire == "waiting" ? .waiting : .completed
    }
}
