import AppKit
import SwiftUI

@MainActor
final class DetailPanel {
    private var panel: NSPanel?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var mouseInsideDetail = false
    private let usage: UsageService?

    init(usage: UsageService? = nil) {
        self.usage = usage
    }

    /// Invoked when the popup's close button is clicked — remove the tab.
    var onClose: ((ReminderItem) -> Void)?

    /// Invoked when the user answers an AskUserQuestion from the popup: the
    /// chosen answer + the question's option count (to build the tty sequence).
    var onAnswer: ((ReminderItem, ItermSendTextAction.Answer, Int) -> Void)?

    /// Invoked for "Chat about this": jump to + maximize the owning pane.
    var onChat: ((ReminderItem) -> Void)?

    static let showDelay: TimeInterval = 0.5
    static let hideGrace: TimeInterval = 0.2
    static let width: CGFloat = 520
    static let minHeight: CGFloat = 84
    static let maxHeightFraction: CGFloat = 0.6

    /// Called by TabStripPanel: item != nil on hover enter, nil on exit.
    func hoverChanged(item: ReminderItem?, tabFrame: CGRect) {
        showWork?.cancel()
        if let item {
            hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.show(item: item, tabFrame: tabFrame) }
            showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
        } else {
            scheduleHide()
        }
    }

    private func show(item: ReminderItem, tabFrame: CGRect) {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let maxHeight = visible.height * Self.maxHeightFraction
        let height = Self.fittingHeight(item: item, usage: usage, width: Self.width, maxHeight: maxHeight)
        let size = CGSize(width: Self.width, height: height)
        let frame = EdgeGeometry.detailFrame(anchoring: tabFrame, size: size, visible: visible)
        // A question popup hosts a text field; it must become key (and main) to
        // receive keyboard focus. Plain popups stay non-key (never steal focus).
        let editable = item.kind == .question
        let panel = self.panel ?? PanelFactory.makePanel(frame: frame, canBecomeKey: true, editable: editable)
        self.panel = panel
        panel.contentViewController = NSHostingController(rootView: DetailView(
            item: item,
            usage: usage,
            onHoverChanged: { [weak self] inside in
                self?.mouseInsideDetail = inside
                if inside { self?.hideWork?.cancel() } else { self?.scheduleHide() }
            },
            onClose: { [weak self] in
                self?.dismiss()
                self?.onClose?(item)
            },
            onAnswer: { [weak self] answer, optionCount in
                self?.dismiss()
                self?.onAnswer?(item, answer, optionCount)
            },
            onChat: { [weak self] in
                self?.dismiss()
                self?.onChat?(item)
            }
        ))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        if editable { panel.makeKey() }
    }

    /// Tear down the popup and cancel any pending show/hide work.
    private func dismiss() {
        showWork?.cancel()
        hideWork?.cancel()
        mouseInsideDetail = false
        panel?.orderOut(nil)
    }

    /// Measure the card's natural height at the given width using a
    /// non-scrolling layout, clamped to [minHeight, maxHeight]. Short messages
    /// yield a compact panel; long ones cap out and scroll.
    private static func fittingHeight(item: ReminderItem, usage: UsageService?, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: DetailView(item: item, usage: usage, scrolls: false).frame(width: width))
        probe.layoutSubtreeIfNeeded()
        let natural = probe.fittingSize.height
        return min(max(natural, minHeight), maxHeight)
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.mouseInsideDetail else { return }
            self.panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideGrace, execute: work)
    }
}

struct DetailView: View {
    let item: ReminderItem
    /// The in-memory usage store; the header reads its latest snapshot each time
    /// the detail is shown (a fresh DetailView per hover) and live-updates via
    /// Observation. nil in the height-measuring probe.
    var usage: UsageService? = nil
    /// true: message scrolls within the (clamped) panel. false: natural
    /// height, used only to measure the content.
    var scrolls: Bool = true
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onAnswer: (ItermSendTextAction.Answer, Int) -> Void = { _, _ in }
    var onChat: () -> Void = {}

    /// Interactive answer controls render only for a single-question
    /// AskUserQuestion; multi-question prompts fall back to the text body plus a
    /// jump (the tty injection sequence is only verified for one question).
    private var interactiveQuestion: NotifyPayload.Question? {
        guard item.kind == .question, item.questions.count == 1 else { return nil }
        return item.questions.first
    }

    /// Live `5h N% · 7d N%` from the current in-memory snapshot, or nil when
    /// there is no data yet (the header then omits the badge). `@MainActor`
    /// because `UsageService.snapshot` is main-actor-isolated; only ever read
    /// from `body`, which is itself main-actor.
    @MainActor private var usageBadge: String? { usage?.snapshot?.badgeText }

    /// Static "2 minutes ago" snapshot computed when the card opens — unlike
    /// SwiftUI's `.relative` style it does not tick like a countdown. Within
    /// the first few seconds (or any near-zero/future clock skew) it reads
    /// "just now" instead of "in 0 seconds".
    private static func relativeTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 10 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        // Abbreviate only the seconds unit ("10 seconds ago" → "10 secs ago");
        // other units keep their full spelling.
        return f.localizedString(for: date, relativeTo: Date())
            .replacingOccurrences(of: "seconds", with: "secs")
    }

    var body: some View {
        let accent = ReminderPalette.color(at: item.colorIndex, level: item.lightenLevel)
        VStack(spacing: 0) {
            // Header: neutral text on a very light wash of the project color.
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.projectName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(Self.relativeTime(item.timestamp))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(.secondary.opacity(0.25), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                    .accessibilityLabel("Close")
                }
                // Second row: branch on the left, usage badge right-aligned.
                // Rendered whenever either is present.
                if item.branchLabel != nil || usageBadge != nil {
                    HStack(spacing: 8) {
                        if let label = item.branchLabel {
                            Label(label, systemImage: item.isWorktree ? "folder" : "arrow.triangle.branch")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if let badge = usageBadge {
                            Text(badge)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.15))

            Divider()

            messageBody
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: scrolls ? .infinity : nil, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(10) // inset within the panel so the shadow is not clipped
        .onHover(perform: onHoverChanged)
    }

    @ViewBuilder private var messageBody: some View {
        if let question = interactiveQuestion {
            let controls = QuestionAnswerView(question: question, onAnswer: onAnswer, onChat: onChat)
            if scrolls {
                ScrollView { controls }
            } else {
                controls
            }
        } else {
            let text = Text(item.fullMessage)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            if scrolls {
                ScrollView { text }
            } else {
                text
            }
        }
    }
}
