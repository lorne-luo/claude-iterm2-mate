# Interactive question answering in toast

## Goal

Let the user answer a single-question AskUserQuestion directly from the toast
notification, replicating the interactive controls that today live only in the
hover-triggered detail popup — so the answer can be given the moment the toast
appears, without waiting for it to demote into a tab and hovering it.

## Background / Confirmed facts

- `QuestionAnswerView` (`Sources/ClaudeItermMate/Panels/QuestionAnswerView.swift`)
  is a self-contained SwiftUI view: option buttons, multiSelect checkboxes +
  Submit, a free-text field + Send, and "Chat about this". It emits
  `(ItermSendTextAction.Answer, optionCount)` via `onAnswer` and a jump via
  `onChat`. It is reusable as-is.
- `DetailPanel`/`DetailView` embeds it only for a single-question prompt
  (`interactiveQuestion`: `item.kind == .question && item.questions.count == 1`,
  `DetailPanel.swift:127-130`), falling back to plain text + jump otherwise.
- The answer/chat behavior already exists in `AppDelegate` and is not
  detail-specific: `detail.onAnswer` injects keystrokes off-main via
  `ItermSendTextAction` then removes the tab (`AppDelegate.swift:59-64`);
  `detail.onChat` focuses+maximizes the pane then removes the tab (`:66-69`).
  The toast will reuse the same logic.
- The toast is presented by `ReminderCoordinator.present` through
  `ToastPanelProtocol.show` (`ToastPanel.swift:6-8`); `ToastView` currently
  renders `item.fullMessage` as plain text and has whole-card tap-to-jump
  (`onTapGesture`, `ToastPanel.swift:215`) plus minimize/close buttons.
- The toast panel is `canBecomeKey` but is never `makeKey`'d, so it never steals
  keyboard focus. The detail panel, by contrast, `makeKey`s on show because it
  is user-invoked (hover) — `DetailPanel.swift:53-78`.
- A `.question` reminder is always focusable: `mate-notify.js handleAsk` drops
  non-iTerm2 sessions (`if (!focusable) return`), so toast question controls
  never face a non-injectable session.
- The waiting toast already pauses its countdown on hover (`onHover` →
  `ToastTimer.pause`), so a user can hover and answer without it expiring.

## Decisions

- Replicate the **full** control set including the free-text field (not just
  click controls).
- Focus timing: the toast stays non-key when it auto-appears and only becomes
  key when the user clicks into the free-text field. Passive appearance must
  never steal the terminal's keyboard focus; option buttons need no focus.
- Only a single-question prompt gets interactive controls in the toast (same
  `interactiveQuestion` rule as detail); multi-question prompts keep the plain
  text body. The rule is extracted to one shared helper used by both panels.
- A question toast drops the whole-card tap-to-jump (it would conflict with the
  embedded controls); "Chat about this" provides the jump instead. Plain toasts
  keep tap-to-jump unchanged.
- Answering (or chatting) from the toast dismisses the toast, cancels its timer,
  and removes the reminder — reusing the existing answer/chat side effects.

## Requirements

- R1: `ToastPanelProtocol.show` / `ToastPanel.show` gain `onAnswer:
  (ItermSendTextAction.Answer, Int) -> Void` and `onChat: () -> Void`
  parameters, mirroring the detail wiring.
- R2: `ToastView` renders `QuestionAnswerView` in its body when the item is an
  interactive single question; otherwise the current plain-text body. The
  whole-card `onTapGesture` is applied only in the non-question case.
- R3: The free-text field becomes editable on click: clicking it makes the toast
  panel key (and only then). `QuestionAnswerView` exposes a focus-begin callback
  the toast wires to `panel.makeKey()`; the detail panel passes a no-op (it is
  already key).
- R4: `ReminderCoordinator` gains injectable `onAnswer` / `onChat` closures
  (like `onActivate`) and passes them into `toastPanel.show`. On answer/chat it
  dismisses the toast, cancels the toast timer, and removes the reminder.
- R5: `AppDelegate` wires `coordinator.onAnswer` / `onChat` to the same
  `sendTextAction` / `focusAction` + `store.remove` logic used for the detail
  panel (single source of truth — no duplicated behavior).
- R6: The single-question predicate is one shared helper (e.g. a `ReminderItem`
  computed property) consumed by both `DetailView` and `ToastView`.

## Acceptance Criteria

- [ ] AC1: `swift build` + full `swift test` + JS suite stay green (no
  regressions; existing toast/detail tests unaffected).
- [ ] AC2: Unit test — the shared single-question predicate returns the question
  only for `kind == .question && questions.count == 1`, nil otherwise.
- [ ] AC3: Unit test — presenting a `.question` reminder and invoking the
  toast's `onAnswer` triggers the coordinator's injected answer closure with the
  right answer + option count and removes the reminder; `onChat` focuses and
  removes.
- [ ] AC4: Manual — a single-question AskUserQuestion toast shows option buttons;
  clicking an option injects the answer into the pane and dismisses the toast.
  multiSelect toggles + Submit works. "Chat about this" jumps.
- [ ] AC5: Manual — the toast does NOT steal keyboard focus when it appears
  (keep typing in the terminal); clicking the free-text field then captures
  focus, typing + Send injects the text answer.
- [ ] AC6: Manual — a multi-question prompt toast still shows plain text (no
  controls); a plain (non-question) toast still jumps on whole-card click.

## Out of scope

- Interactive answering for multi-question prompts (kept as text + jump, same as
  detail today).
- Changing the toast countdown / demote-to-tab timing.
- Any change to `ItermSendTextAction` tty sequences (already verified/tested).
- Non-iTerm2 (non-focusable) sessions (never reach a question toast).
