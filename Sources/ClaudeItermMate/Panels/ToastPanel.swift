import AppKit
import SwiftUI

@MainActor
protocol ToastPanelProtocol: AnyObject {
    func show(item: ReminderItem, on visible: CGRect, showsMinimize: Bool,
              onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
              onMinimize: @escaping () -> Void, onClose: @escaping () -> Void,
              onAnswer: @escaping (ItermSendTextAction.Answer, Int) -> Void,
              onChat: @escaping () -> Void,
              onJumpMaximized: @escaping () -> Void,
              onQuickReply: @escaping (QuickReply) -> Void)
    /// Dismiss the toast. `intoTab` true → shrink toward the tab strip (it is
    /// becoming a tab); false → fade out in place (it is being dropped, so a
    /// fly-into-the-strip animation would be misleading — nothing lands there).
    func hide(intoTab: Bool)
}

@MainActor
final class ToastPanel: ToastPanelProtocol {
    private var panel: NSPanel?

    /// The shown item and the screen rect it was laid out against, kept only so the
    /// expand toggle can re-measure and re-frame the panel. Cleared on dismiss/hide
    /// so a late toggle callback cannot resize a gone toast.
    private var shownItem: ReminderItem?
    private var shownVisible: CGRect = .zero
    /// Whether the shown toast carries the chevron — its row must be included when
    /// re-measuring on toggle, or the message loses its last line.
    private var shownShowsToggle = false
    /// Same story for the quick-reply row: it is another ~24pt the re-measure
    /// must account for.
    private var shownShowsQuickReplies = false

    private let usage: UsageService?

    init(usage: UsageService? = nil) {
        self.usage = usage
    }

    static let width: CGFloat = 440
    static let minHeight: CGFloat = 56
    /// Last-resort cap so the card cannot run off-screen — `EdgeGeometry.toastFrame`
    /// does no clamping of its own. Short content still sizes down naturally, and a
    /// question's options / an expanded message scroll within the card once they
    /// hit this. Sized to stay on-screen at the smallest supported display
    /// (1280×800 → visibleFrame height ≈ 775, so 700 + the 12pt margin fits).
    static let maxHeight: CGFloat = 700

    func show(item: ReminderItem, on visible: CGRect, showsMinimize: Bool,
              onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
              onMinimize: @escaping () -> Void, onClose: @escaping () -> Void,
              onAnswer: @escaping (ItermSendTextAction.Answer, Int) -> Void,
              onChat: @escaping () -> Void,
              onJumpMaximized: @escaping () -> Void,
              onQuickReply: @escaping (QuickReply) -> Void) {
        hide(intoTab: false)
        // Whether to offer the chevron is decided from two toggle-less heights, so
        // the comparison is apples-to-apples; only then is the final height measured
        // *with* the chevron. Skipping that last pass cost exactly the chevron's
        // row (~16pt) and clipped the message's last line. Only a plain toast pays
        // for the extra passes — a question is never `lineLimit`-truncated, its
        // height already follows its options.
        // Quick replies need a session we can send keystrokes to — the same
        // condition the minimize button already carries.
        let showsQuickReplies = showsMinimize
        let bare = fittingHeight(item: item, expanded: false, toggle: false,
                                 quickReplies: showsQuickReplies)
        let showsExpandToggle = item.kind == .question
            ? false
            : Self.needsExpandToggle(collapsed: bare,
                                     expanded: fittingHeight(item: item, expanded: true, toggle: false,
                                                             quickReplies: showsQuickReplies))
        let height = showsExpandToggle
            ? fittingHeight(item: item, expanded: false, toggle: true,
                            quickReplies: showsQuickReplies)
            : bare
        let frame = EdgeGeometry.toastFrame(size: CGSize(width: Self.width, height: height), visible: visible)
        // canBecomeKey so the SwiftUI tap gesture receives the click. The panel
        // is NOT made key here — a passively-shown toast must not steal the
        // terminal's keyboard focus. It only becomes key when the user clicks the
        // free-text field (onEditingBegan below), so an interactive question can
        // be typed into without the toast hijacking focus on appearance. A
        // question toast must also be `editable` (main-eligible): the field
        // editor behind the answer TextField needs main status, so key alone
        // leaves it un-typable — the same fix DetailPanel needed.
        let panel = PanelFactory.makePanel(
            frame: frame, canBecomeKey: true, editable: item.kind == .question
        )
        panel.contentView = FirstMouseHostingView(rootView: ToastView(
            item: item,
            usage: usage,
            onTap: { [weak self] in
                self?.dismiss()
                onClick()
            },
            onHover: onHover,
            showsMinimize: showsMinimize,
            onMinimize: onMinimize,
            onClose: onClose,
            onAnswer: onAnswer,
            onChat: onChat,
            onJumpMaximized: onJumpMaximized,
            onEditingBegan: { [weak panel] in panel?.makeKey() },
            showsExpandToggle: showsExpandToggle,
            onToggleExpand: { [weak self] expanded in self?.regrow(expanded: expanded) },
            showsQuickReplies: showsQuickReplies,
            // No self-dismiss: the coordinator tears the toast down (cancel timer,
            // drop the item) exactly as it does for an answer.
            onQuickReply: onQuickReply
        ))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        shownItem = item
        shownVisible = visible
        shownShowsToggle = showsExpandToggle
        shownShowsQuickReplies = showsQuickReplies
    }

    /// Re-measure for the new expansion state and re-frame the panel. Because
    /// `toastFrame` derives y from `maxY - margin - height`, the top edge stays put
    /// and the card grows downward. Runs before SwiftUI relayouts (the `@State`
    /// flip is only marked dirty here), so the panel is already big enough when the
    /// expanded content draws — never a clipped frame.
    private func regrow(expanded: Bool) {
        guard let panel, let item = shownItem else { return }
        let height = fittingHeight(item: item, expanded: expanded, toggle: shownShowsToggle,
                                   quickReplies: shownShowsQuickReplies)
        let frame = EdgeGeometry.toastFrame(size: CGSize(width: Self.width, height: height),
                                            visible: shownVisible)
        panel.setFrame(frame, display: true)
    }

    /// Natural height of the toast card at `width`, clamped to [min, max], so a
    /// short message doesn't leave a tall blank card. Mirrors DetailPanel.
    /// `expanded` measures the un-truncated message (the expanded state), which is
    /// both the height to grow to on toggle and the input to `needsExpandToggle`.
    /// `usage` must be passed (as DetailPanel does) and `toggle` must match what the
    /// live view renders: both the meters and the chevron add height the probe would
    /// otherwise miss, and the shortfall clipped the message's last line.
    private func fittingHeight(item: ReminderItem, expanded: Bool, toggle: Bool,
                               quickReplies: Bool) -> CGFloat {
        let probe = NSHostingView(
            rootView: ToastView(item: item, usage: usage, scrolls: false,
                                measuresExpanded: expanded, showsExpandToggle: toggle,
                                showsQuickReplies: quickReplies)
                .frame(width: Self.width)
        )
        probe.layoutSubtreeIfNeeded()
        return min(max(probe.fittingSize.height, Self.minHeight), Self.maxHeight)
    }

    /// Whether the collapsed message is actually truncated — i.e. expanding would
    /// reveal something. Asking "would it get taller?" avoids estimating wrapped
    /// line counts, which is unreliable at 440pt for mixed CJK/latin text (a CJK
    /// glyph is ~2× a latin one). Equal heights also cover the case where both
    /// states are already pinned to `maxHeight`: expanding shows nothing new.
    /// The 1pt tolerance absorbs layout/float jitter.
    nonisolated static func needsExpandToggle(collapsed: CGFloat, expanded: CGFloat) -> Bool {
        expanded > collapsed + 1
    }

    /// Immediate close (no fly-in) — used when the toast is clicked, since we're
    /// jumping to the pane rather than queuing a tab.
    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        shownItem = nil
    }

    /// Dismiss the toast. When it is becoming a tab, shrink toward the right
    /// screen edge (vertical center, where the strip lives) while fading — a
    /// fly-into-the-strip effect. When it is being dropped (unfindable / closed)
    /// there is no tab to fly into, so just fade out in place.
    func hide(intoTab: Bool) {
        guard let panel else { return }
        self.panel = nil
        shownItem = nil
        // The fade/fly-out lasts 0.2–0.35 s during which the panel is still on
        // screen and still hit-testable, but the coordinator has already dropped
        // its `displayed` token — a click landing here is silently discarded
        // (`guard displayed?.token == token`). Stop taking clicks the moment the
        // toast starts dying, so the press falls through to whatever is behind.
        panel.ignoresMouseEvents = true
        guard intoTab else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            return
        }
        let visible = NSScreen.main?.visibleFrame ?? panel.frame
        let target = CGRect(
            x: visible.maxX - EdgeGeometry.tabWidth,
            y: visible.midY - EdgeGeometry.tabHeight / 2,
            width: EdgeGeometry.tabWidth,
            height: EdgeGeometry.tabHeight
        )
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

struct ToastView: View {
    let item: ReminderItem
    var usage: UsageService? = nil
    /// true: a question's answer controls scroll within the (clamped) card.
    /// false: natural height, used only by `fittingHeight` to measure. Without
    /// this, a question with many options overflowed the 360pt cap and the card
    /// silently clipped its own title row, close button and Send/Chat controls.
    var scrolls: Bool = true
    /// Forces the expanded (un-truncated) message layout. Used **only** by
    /// `fittingHeight`'s probe, which never runs `onAppear` and so cannot seed
    /// `@State`. The live view leaves this false and drives expansion through
    /// `expanded` instead — two sources, so neither needs a custom `init`.
    var measuresExpanded: Bool = false
    var onTap: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var showsMinimize: Bool = false
    var onMinimize: () -> Void = {}
    var onClose: () -> Void = {}
    var onAnswer: (ItermSendTextAction.Answer, Int) -> Void = { _, _ in }
    var onChat: () -> Void = {}
    /// Double-click on the title row: always jump to the *maximized* pane,
    /// regardless of the maximize-on-click toggle. Works for question toasts too,
    /// whose card has no single-click jump.
    var onJumpMaximized: () -> Void = {}
    var onEditingBegan: () -> Void = {}
    /// Whether to offer the expand chevron — true only when the collapsed message
    /// is really truncated (decided by `ToastPanel.needsExpandToggle`).
    var showsExpandToggle: Bool = false
    /// Reports the new expansion state so the panel can re-measure and re-frame.
    var onToggleExpand: (Bool) -> Void = { _ in }
    /// The quick-reply row at the card's bottom edge; false for a session we
    /// cannot send keystrokes to (nothing to send them at).
    var showsQuickReplies: Bool = false
    var onQuickReply: (QuickReply) -> Void = { _ in }
    /// Drives the waiting toast's bright-white breathing glow (matches the tab).
    @State private var breathe = false
    /// Live expansion state; see `measuresExpanded` for why the probe uses its own.
    @State private var expanded = false

    /// Interactive answer controls render only for a single-question
    /// AskUserQuestion (shared rule with DetailView); otherwise plain text.
    private var interactiveQuestion: NotifyPayload.Question? { item.interactiveQuestion }

    private var isWaiting: Bool { item.status == .waiting }

    /// Character budget for the toast title at 360pt / 13pt semibold.
    static let titleBudget = 42

    /// `project · branch` when it fits within `titleBudget`; otherwise the
    /// branch is truncated (with an ellipsis), and dropped entirely if even the
    /// project alone leaves no room.
    static func title(project: String, branch: String?) -> String {
        let base = project
        guard let branch, !branch.isEmpty else { return base }
        let full = "\(base) · \(branch)"
        if full.count <= titleBudget { return full }
        let prefix = "\(base) · "
        let room = titleBudget - prefix.count - 1 // reserve 1 for the ellipsis
        guard room >= 1 else { return base }
        return prefix + branch.prefix(room) + "…"
    }

    /// Live snapshot backing the usage meters, or nil when there is no data yet —
    /// the title row then renders exactly as before. `@MainActor` because
    /// `UsageService.snapshot` is main-actor-isolated; only ever read from `body`,
    /// which is itself main-actor.
    @MainActor private var usageSnapshot: UsageSnapshot? { usage?.snapshot }

    /// A small circular control (minimize / close) in the toast's top-right.
    /// `.buttonStyle(.plain)` keeps the tap from bubbling to the card's
    /// `onTapGesture`, which jumps to the pane.
    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
                .background(.secondary.opacity(0.25), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// The reply text, or the interactive answer controls for a single-question
    /// AskUserQuestion.
    @ViewBuilder private var messageBody: some View {
        if let question = interactiveQuestion {
            let controls = QuestionAnswerView(
                question: question,
                onAnswer: onAnswer,
                onChat: onChat,
                onEditingBegan: onEditingBegan
            )
            .padding(.horizontal, -4) // QuestionAnswerView pads 16; trim inside the toast
            if scrolls {
                ScrollView { controls }
            } else {
                controls
            }
        } else {
            let text = Text(item.fullMessage)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 10)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Expanded content can exceed `maxHeight`; without a ScrollView the card
            // would silently clip the tail, which is worse than the collapsed
            // ellipsis. Collapsed stays exactly as before (no ScrollView).
            if isExpanded && scrolls {
                ScrollView { text }
            } else {
                text
            }
        }
    }

    /// The full message is shown when the user expanded it, or when the measuring
    /// probe asked for the expanded layout.
    private var isExpanded: Bool { measuresExpanded || expanded }

    /// Centered under the message: grows the toast downward to the full reply.
    /// `.buttonStyle(.plain)` is required — otherwise the tap bubbles to the card's
    /// `onTapGesture` and jumps to the pane (same reason as `iconButton`).
    private var expandToggle: some View {
        Button {
            expanded.toggle()
            onToggleExpand(expanded)
        } label: {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Collapse" : "Show full message")
        .accessibilityLabel(expanded ? "Collapse" : "Show full message")
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Project-color bar ties the toast to its right-edge tab.
            RoundedRectangle(cornerRadius: 2)
                .fill(ReminderPalette.color(at: item.colorIndex, level: item.lightenLevel))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                // The minimize/close controls live INSIDE the title row rather than
                // as a third column of this HStack. As a column they shortened the
                // whole VStack, so an expanded message's `ScrollView` ended its
                // scrollbar 48pt short of the card's right edge (their width plus
                // the HStack spacing). In the title row they still reserve their
                // room — the title truncates against them — while the body and its
                // scrollbar now run the full width of the card.
                ToastTitleRow(
                    title: Self.title(project: item.projectName, branch: item.branchLabel),
                    snapshot: usageSnapshot,
                    singleClickJumps: interactiveQuestion == nil,
                    onTap: onTap,
                    onJumpMaximized: onJumpMaximized
                ) {
                    if showsMinimize {
                        iconButton("minus", label: "Minimize to tab", action: onMinimize)
                    }
                    iconButton("xmark", label: "Close", action: onClose)
                }
                messageBody
                if showsExpandToggle {
                    expandToggle
                }
                if showsQuickReplies {
                    QuickReplyBar(onQuickReply: onQuickReply)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        // Waiting: a bright-white breathing border + glow so the toast and the
        // tab it becomes read as one.
        .overlay {
            if isWaiting {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(ReminderPalette.waitingAccent.opacity(breathe ? 1 : 0.5), lineWidth: 2)
                    .shadow(color: ReminderPalette.waitingAccent.opacity(breathe ? 0.8 : 0.25),
                            radius: breathe ? 9 : 3)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
        .onAppear {
            guard isWaiting else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .padding(8) // inset within the panel so the shadow is not clipped
        .contentShape(Rectangle())
        // Whole-card tap-to-jump only for non-question toasts. A question card
        // hosts controls; a background tap must not jump — "Chat about this"
        // provides the jump instead.
        .tapToJump(interactiveQuestion == nil, action: onTap)
        .onHover(perform: onHover)
        // The card cannot be a Button (it embeds buttons, and the title row
        // needs a 2-count gesture), so its semantics are declared explicitly:
        // one focusable element with both jump actions exposed to VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.title(project: item.projectName, branch: item.branchLabel))
        .accessibilityAction(named: "Jump to pane") { onTap() }
        .accessibilityAction(named: "Jump to maximized pane") { onJumpMaximized() }
    }
}

/// Project · branch, the usage meters and the card's minimize/close controls,
/// plus the row's own click handling: double-click always jumps to the maximized
/// pane, single-click mirrors the card (the row's 2-count gesture would otherwise
/// swallow it). Extracted from `ToastView` so each view body stays small enough to
/// type-check quickly and diff independently. `controls` is injected rather than
/// built here so `iconButton` can stay on `ToastView` next to its sibling buttons.
private struct ToastTitleRow<Controls: View>: View {
    let title: String
    let snapshot: UsageSnapshot?
    /// False for a question toast, whose card intentionally has no jump-on-click.
    let singleClickJumps: Bool
    let onTap: () -> Void
    let onJumpMaximized: () -> Void
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let snapshot {
                // No percents here: the meters must not squeeze the title.
                UsageBadgeView(snapshot: snapshot, showsPercent: false)
                    .fixedSize()
            }
            controls()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onJumpMaximized)
        .tapToJump(singleClickJumps, action: onTap)
    }
}

private extension View {
    /// Attach the whole-card tap gesture only when `enabled`; otherwise leave the
    /// view untouched so embedded controls own every tap.
    @ViewBuilder
    func tapToJump(_ enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled { onTapGesture(perform: action) } else { self }
    }
}
