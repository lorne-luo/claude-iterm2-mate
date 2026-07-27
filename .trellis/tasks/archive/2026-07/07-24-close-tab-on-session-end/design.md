# Design — Close tab on SessionEnd + lazy GC

## Two independent mechanisms

### A. SessionEnd → clear tab (event-driven)

```
SessionEnd hook (mate-notify.js --event session-end)
  --socket--> {type:"resolve", session_uuid, cwd, timestamp}
  NotifyPayload(isResolve) -> ReminderCoordinator.handle -> store.remove(sessionUUID)
```

Pure reuse of the existing `resolve` branch (`ReminderCoordinator.swift:114`).
No coordinator/store changes — only a new JS handler + hook registration.

`handleSessionEnd(raw)` mirrors `handleAskDone` exactly (guards: darwin, not
SDK, focusable), emitting the same `resolve` payload. Wire `HANDLERS["session-end"]`
and teach `eventMode` to accept `"session-end"`.

### B. Pane closed → GC in-memory state (lazy reconcile)

The reminder path already runs one off-main probe per event. Change it from
`canFind` to `liveSessionIDs`, then reconcile before presenting:

```swift
// ReminderCoordinator.handle, reminder branch
DispatchQueue.global(qos: .userInitiated).async { [weak self] in
    let live = probe.liveSessionIDs()                       // Set<String>? (nil = unknown)
    let findable = live?.contains(p.sessionUUID) ?? probe.canFind(p.sessionUUID)
    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if let live { self.reconcile(live: live) }          // GC only when set is known
        self.present(p, findable: findable)
    }
}
```

`live?.contains(...) ?? canFind(...)` short-circuits: when `live != nil` the
extra `canFind` (a second `it2` spawn) is never evaluated. For stubs whose
`liveSessionIDs()` defaults to `nil`, it falls back to `canFind` — so every
existing coordinator/coloring test keeps its exact current behavior and reconcile
never runs under them.

```swift
private func reconcile(live: Set<String>) {
    coloredSessions = coloredSessions.filter { live.contains($0.key) }
    colorInjectedSessions = colorInjectedSessions.filter { live.contains($0) }
    for dead in store.items.map(\.sessionUUID) where !live.contains(dead) {
        store.remove(sessionUUID: dead)                     // R8 dead-tab backstop
    }
}
```

## Protocol contract change

```swift
protocol ItermSessionProbe: Sendable {
    func canFind(_ uuid: String) -> Bool
    func liveSessionIDs() -> Set<String>?
}
extension ItermSessionProbe {
    func liveSessionIDs() -> Set<String>? { nil }   // default: unknown -> no GC
}
```

`ItermSessionLookup` already implements `liveSessionIDs()` (overrides the
default). Its `canFind` stays as-is. No production caller of `canFind` other
than the reminder path is affected.

## Safety / ordering

- Reconcile runs on the main actor, before `present()`. The current event's
  session, if alive, is in `live` and survives; if already closed it is GC'd and
  `present()` won't build a tab (`findable == false`). No self-deletion race.
- `live == nil` (probe failure / `it2` missing) skips reconcile entirely — a
  transient failure never wipes live sessions' color memory or tabs.
- `session_start` / `resolve` branches return before the reminder probe, so they
  never trigger reconcile (keeps SessionStart coloring on its fast synchronous
  path). GC piggybacks on the next reminder event of any session.
- `SessionEnd`'s `resolve` intentionally leaves color memory intact (Goal #1).

## Compatibility / rollout

- New hook propagates on next app launch via the idempotent `install()` upgrade
  path; existing users need no reinstall.
- Wire protocol unchanged (reuses `resolve`); no `NotifyPayload` field added.

## Rollback

Each half is independent. Reverting the JS `session-end` handler + hook lines
disables A; reverting the probe/reconcile change disables B. Neither touches the
Stop/Notification/ask paths.
