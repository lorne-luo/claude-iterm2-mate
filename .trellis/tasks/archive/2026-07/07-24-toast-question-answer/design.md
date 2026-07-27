# Design — Interactive question answering in toast

## Shared predicate (R6)

Extract the single-question rule out of `DetailView` into one place both panels
use:

```swift
extension ReminderItem {
    /// The lone question when this reminder is an interactive single-question
    /// AskUserQuestion; nil otherwise (plain reminders and multi-question
    /// prompts render as text). tty injection is only verified for one question.
    var interactiveQuestion: NotifyPayload.Question? {
        guard kind == .question, questions.count == 1 else { return nil }
        return questions.first
    }
}
```

`DetailView.interactiveQuestion` (`DetailPanel.swift:127`) becomes a thin
reference to this; `ToastView` uses the same. Pure, unit-testable (AC2).

## Toast panel signature + focus (R1, R3)

`ToastPanelProtocol.show` and `ToastPanel.show` gain:

```swift
onAnswer: @escaping (ItermSendTextAction.Answer, Int) -> Void,
onChat: @escaping () -> Void
```

`QuestionAnswerView` gains one optional callback:

```swift
var onEditingBegan: () -> Void = {}   // fired when the free-text field gains focus
```

wired inside via `@FocusState` on the `TextField` (or `.onTapGesture` on the
field) → `onEditingBegan()`. The toast passes `{ [weak panel] in panel?.makeKey() }`;
the detail panel passes the default no-op (it already `makeKey`s on show).

Focus mechanics: the toast panel stays non-key on `orderFrontRegardless()`. When
the user clicks the field, `onEditingBegan` runs `panel.makeKey()` so the field
can become first responder and accept typing. Because a `nonactivating`
`canBecomeKey` panel may not reliably route the very first click into the field
before it is key, `makeKey()` is called on the field's focus/tap; a second click
is an acceptable fallback if the first only keys the window. **GUI-only — verify
live (AC5); not unit-testable.**

## ToastView body (R2)

```swift
if let question = item.interactiveQuestion {
    QuestionAnswerView(question: question, onAnswer: onAnswer, onChat: onChat,
                       onEditingBegan: onEditingBegan)   // no whole-card tap
} else {
    // existing fullMessage text
}
```

- Whole-card `.onTapGesture(perform: onTap)` is applied only in the else branch
  (a question card must not jump on background taps that miss a control).
- `QuestionAnswerView`'s buttons already use `.buttonStyle(.plain)`, which
  consumes taps and keeps them off any card gesture (same pattern that lets the
  existing minimize/close buttons coexist).
- Height: reuse the existing `fittingHeight` clamp; wrap tall control stacks in
  the toast the same way detail does (ScrollView when clamped). Verify a
  many-option question does not overflow (AC4, live).

## Coordinator wiring (R4)

`ReminderCoordinator` gains injected closures paralleling `onActivate`:

```swift
var onAnswer: ((ReminderItem, ItermSendTextAction.Answer, Int) -> Void)?
var onChat: ((ReminderItem) -> Void)?
```

In `present`, the `toastPanel.show(...)` call passes:

```swift
onAnswer: { [weak self] answer, count in
    self?.dismissToast(token: token, session: session)   // cancel timer + hide + remove
    self?.onAnswer?(item, answer, count)
},
onChat: { [weak self] in
    self?.dismissToast(token: token, session: session)
    self?.onChat?(item)
}
```

`dismissToast` reuses the `complete(token:session:findable:false)` teardown (it
cancels the timer, hides the panel, and — with findable=false — removes the item
via `removeIfCurrent`) OR calls `store.remove` directly + hides; pick whichever
keeps the token guard intact so a stale timer can't fire afterward. The actual
answer injection / focus lives in the AppDelegate closures (below), same as the
click-to-jump path via `onActivate`.

## AppDelegate wiring (R5)

```swift
coordinator.onAnswer = { [weak self] item, answer, count in
    DispatchQueue.global(qos: .userInitiated).async {
        sendTextAction.answer(sessionUUID: item.sessionUUID, answer: answer, optionCount: count)
    }
    self?.store.remove(sessionUUID: item.sessionUUID)
}
coordinator.onChat = { [weak self] item in
    self?.focusAction.focus(sessionUUID: item.sessionUUID, maximize: true)
    self?.store.remove(sessionUUID: item.sessionUUID)
}
```

Identical to the existing `detail.onAnswer`/`detail.onChat` bodies
(`AppDelegate.swift:59-69`) — factor into shared closures so detail and toast
share one implementation (no divergence).

## Compatibility / rollback

- Protocol change to `ToastPanelProtocol.show` breaks the test `SpyToast`
  (`ReminderCoordinatorTests.swift:15`); update its signature (add the two
  params, record them) — this is also how AC3 asserts the wiring.
- No wire/payload change; no hook change. Purely UI + in-process wiring.
- Rollback: revert `ToastView`/`ToastPanel`/coordinator wiring; detail path is
  untouched and keeps working. The shared predicate extension is inert on its own.

## Risk notes

- The focus/makeKey behavior is the only genuinely uncertain piece and is
  GUI-only. Budget a live iteration; keep it isolated in `onEditingBegan` so a
  fallback (e.g. key-on-hover) is a one-line change if click-to-key misbehaves.
