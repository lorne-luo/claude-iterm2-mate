# Implement — Interactive question answering in toast

## Ordered checklist

1. `Store/ReminderStore.swift` (or a small `ReminderItem+Question.swift`): add
   the shared `interactiveQuestion` computed property on `ReminderItem`.
   → verify: `swift build`.
2. `Panels/DetailPanel.swift`: replace `DetailView.interactiveQuestion` body
   with `item.interactiveQuestion` (no behavior change).
3. `Panels/QuestionAnswerView.swift`: add `var onEditingBegan: () -> Void = {}`;
   fire it when the free-text field gains focus (`@FocusState` change or field
   tap). Detail path passes the default (no-op).
4. `Panels/ToastPanel.swift`:
   - extend `ToastPanelProtocol.show` + `ToastPanel.show` with `onAnswer` /
     `onChat` params;
   - in `ToastView`, branch the body on `item.interactiveQuestion` → render
     `QuestionAnswerView` (wiring onAnswer/onChat/onEditingBegan), else the
     existing text; apply the whole-card `onTapGesture` only in the else branch;
   - pass `onEditingBegan: { [weak panel] in panel?.makeKey() }` from `show`.
5. `ReminderCoordinator.swift`: add `onAnswer` / `onChat` closures; pass them
   into `toastPanel.show`, wrapping each to also tear down the toast (cancel
   timer + hide + remove via the token-guarded path) before invoking the
   injected closure.
6. `AppDelegate.swift`: wire `coordinator.onAnswer` / `onChat`; factor the
   answer/chat bodies shared with `detail.onAnswer`/`onChat` so both use one
   implementation.

### Tests
7. `Tests/ClaudeItermMateTests/`: unit-test `ReminderItem.interactiveQuestion`
   (AC2).
8. `Tests/ClaudeItermMateTests/ReminderCoordinatorTests.swift`: update `SpyToast`
   to the new `show` signature, capturing `onAnswer`/`onChat`; add a test that
   presenting a single-question `.question` reminder and firing the spy's
   `onAnswer` calls `coordinator.onAnswer` with the expected answer + option
   count and removes the item; `onChat` likewise (AC3).

## Validation commands
```
swift build
swift test --filter ReminderCoordinatorTests
swift test                     # full suite, no regressions (AC1)
node --test 'Tests/js/**/*.test.js'
./run.sh                       # build+install+launch for manual AC4/AC5/AC6
```
Manual (AC4/AC5/AC6): trigger a single-question AskUserQuestion in an iTerm2
Claude session; on the toast, click an option (injects + dismisses), test
multiSelect + Submit, click the free-text field (must NOT have stolen focus
before the click), type + Send, and "Chat about this". Confirm a multi-question
prompt toast stays plain text and a normal Stop toast still jumps on card click.

## Risky files / rollback points
- `ToastPanelProtocol.show` signature — breaks `SpyToast`; update in the same
  change (also serves AC3).
- Focus/`makeKey` on field click — GUI-only, the one uncertain piece; isolated
  in `onEditingBegan` so switching the trigger (e.g. to hover) is one line.
- Whole-card tap vs embedded controls — ensure `.plain` buttons consume taps and
  the card gesture is absent on the question branch (avoid accidental jumps).
- Coordinator teardown — keep the toast timer token guard so a stale timer never
  fires after an answer removes the item.
