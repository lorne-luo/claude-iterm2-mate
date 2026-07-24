# Implement — Close tab on SessionEnd + lazy GC

## Ordered checklist

### Part A — SessionEnd clears the tab
1. `Resources/mate-notify.js`: add `handleSessionEnd(raw)` (copy of
   `handleAskDone`, same guards, same `resolve` payload).
   → verify: node syntax OK.
2. `mate-notify.js`: `eventMode` accepts `"session-end"`; add
   `"session-end": handleSessionEnd` to `HANDLERS`.
   → verify: `eventMode(["--event","session-end"])` returns `"session-end"`.
3. `Hook/HookInstaller.swift`: add `sessionEndHookCommand(scriptPath:)` and a
   `settingsByAddingHook(..., event:"SessionEnd", marker:"mate-notify.js")` call
   in `install()`; add matching `settingsByRemovingHook(..., event:"SessionEnd")`
   in `uninstall()`.
   → verify: HookInstallerTests (below).

### Part B — lazy reconcile GC
4. `Actions/ItermSessionLookup.swift`: add `liveSessionIDs() -> Set<String>?` to
   the `ItermSessionProbe` protocol + a protocol-extension default returning `nil`.
   → verify: `swift build` (existing stubs still compile).
5. `ReminderCoordinator.swift`: in the reminder branch of `handle`, fetch
   `probe.liveSessionIDs()`, derive `findable` via `live?.contains(...) ?? canFind(...)`,
   call `reconcile(live:)` on main when `live != nil`, then `present`.
6. `ReminderCoordinator.swift`: add `private func reconcile(live:)` (filter
   `coloredSessions`, `colorInjectedSessions`; remove dead `store` items).

### Tests
7. `Tests/js/mate-notify.test.js`: add `eventMode` session-end case.
8. `Tests/ClaudeItermMateTests/HookInstallerTests.swift`: SessionEnd add-once /
   idempotent-on-rerun / remove cases.
9. `Tests/ClaudeItermMateTests/ReminderCoordinatorTests.swift`: a stub returning
   a controllable live set; assert GC of absent color/flag entries + dead tabs,
   retention of present ones, and no-GC when `liveSessionIDs()` is `nil`.

## Validation commands
```
node --test 'Tests/js/**/*.test.js'
swift build
swift test --filter HookInstallerTests
swift test --filter ReminderCoordinatorTests
swift test                                   # full suite before finishing
```
Manual: `make build && make install`, then AC4 in prd.md.

## Risky files / rollback points
- `mate-notify.js` — shared by 5 hooks; keep new code isolated in
  `handleSessionEnd`, do not touch existing handlers.
- `HookInstaller.swift` — writes the real `~/.claude/settings.json`; tests must
  only exercise the pure `settingsBy*` transforms, never the real file.
- `ItermSessionProbe` protocol change — the extension default is what keeps the
  three existing stubs compiling; verify with `swift build` right after step 4.
- Reconcile ordering — GC must run only when `live != nil` and before `present`.
