import AppKit
import SwiftUI

@MainActor
final class TabStripPanel {
    private let store: ReminderStore
    private let onClick: (ReminderItem) -> Void
    private let onHover: (ReminderItem?, CGRect) -> Void
    private let onClearAll: () -> Void
    private var panel: NSPanel?
    /// Reused across renders: assigning `rootView` diffs the strip in place,
    /// whereas replacing the hosting view discards every tab's SwiftUI state —
    /// hover highlight and the waiting breathing animation restarted on each
    /// store mutation.
    private var host: FirstMouseHostingView<TabStripView>?

    init(
        store: ReminderStore,
        onClick: @escaping (ReminderItem) -> Void,
        onHover: @escaping (ReminderItem?, CGRect) -> Void,
        onClearAll: @escaping () -> Void
    ) {
        self.store = store
        self.onClick = onClick
        self.onHover = onHover
        self.onClearAll = onClearAll
        observe()
    }

    /// Re-render on every store mutation via Observation's onChange hook.
    private func observe() {
        withObservationTracking {
            _ = store.items
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.render()
                self?.observe()
            }
        }
        render()
    }

    private func render() {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let queued = Array(store.queued.prefix(EdgeGeometry.maxVisibleTabs(visible: visible)))
        guard !queued.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        // A tab is always visible here (empty is handled above), so the
        // "close all" tab always accompanies the strip.
        let frame = EdgeGeometry.stripFrame(tabCount: queued.count, hasCloser: true, visible: visible)
        let panel = self.panel ?? Self.makeStripPanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        let root = TabStripView(
            items: queued,
            onClick: onClick,
            onHover: { [weak self] item, index in
                guard let self, let panel = self.panel else { return }
                guard let item, let index else {
                    self.onHover(nil, .zero)
                    return
                }
                let tabFrame = EdgeGeometry.tabFrame(index: index, stripFrame: panel.frame)
                self.onHover(item, tabFrame)
            },
            onClearAll: onClearAll
        )
        if let host {
            host.rootView = root
        } else {
            let host = FirstMouseHostingView(rootView: root)
            panel.contentView = host
            self.host = host
        }
        panel.orderFrontRegardless()
    }

    private static func makeStripPanel() -> NSPanel {
        PanelFactory.makePanel(frame: .zero, canBecomeKey: true)
    }
}

struct TabStripView: View {
    let items: [ReminderItem]
    let onClick: (ReminderItem) -> Void
    let onHover: (ReminderItem?, Int?) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(spacing: EdgeGeometry.tabSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                // Button (not onTapGesture) so VoiceOver sees a control and the
                // tab gets focus handling for free; `.plain` keeps the visuals.
                Button { onClick(item) } label: {
                    EdgeTabView(item: item)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    onHover(inside ? item : nil, inside ? index : nil)
                }
                .help(Self.tooltip(item))
                .accessibilityLabel(Self.tooltip(item))
                .accessibilityHint("Jumps to this session's iTerm2 pane")
            }
            Button(action: onClearAll) { CloserTabView() }
                .buttonStyle(.plain)
                .help("Clear all reminders")
                .accessibilityLabel("Clear all reminders")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude session reminders")
    }

    /// `project · branch — waiting` — the tab shows only a glyph, so this is the
    /// only place its identity is spelled out (tooltip and VoiceOver alike).
    static func tooltip(_ item: ReminderItem) -> String {
        var text = item.projectName
        if let branch = item.branchLabel { text += " · \(branch)" }
        return item.status == .waiting ? "\(text) — waiting for you" : text
    }
}

// Named EdgeTabView to avoid shadowing SwiftUI.TabView.
private struct EdgeTabView: View {
    let item: ReminderItem
    @State private var hovering = false
    /// Drives the bright-white breathing pulse on a waiting tab. Toggled true on
    /// appear / on a flip to waiting via `withAnimation(.repeatForever)`; ignored
    /// (and the overlay/glow removed) while completed.
    @State private var breathe = false

    private var isWaiting: Bool { item.status == .waiting }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 11, bottomLeadingRadius: 11,
            bottomTrailingRadius: 0, topTrailingRadius: 0
        )
    }

    var body: some View {
        let identity = item.identity
        let base = ReminderPalette.color(at: item.colorIndex, level: item.lightenLevel)
        glyph(identity)
            .foregroundStyle(ReminderPalette.glyphForeground(at: item.colorIndex, level: item.lightenLevel))
            .frame(width: EdgeGeometry.tabWidth, height: EdgeGeometry.tabHeight)
            .background {
                // Subtle top-to-bottom sheen over the project color for depth.
                LinearGradient(
                    colors: [base.opacity(0.92), base],
                    startPoint: .top, endPoint: .bottom
                )
                .overlay(Color.white.opacity(hovering ? 0.18 : 0)) // instant hover feedback
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(hovering ? 0.5 : 0.12), lineWidth: 1))
            // Waiting: a bright-white breathing border over the project color
            // (project color and glyph stay untouched — status is an additional
            // signal). Opacity + glow pulse together on the `breathe` flag.
            .overlay {
                if isWaiting {
                    shape.strokeBorder(
                        ReminderPalette.waitingAccent.opacity(breathe ? 1 : 0.5),
                        lineWidth: 2
                    )
                }
            }
            .shadow(
                color: isWaiting ? ReminderPalette.waitingAccent.opacity(breathe ? 0.9 : 0.3) : .clear,
                radius: isWaiting ? (breathe ? 9 : 3) : 0
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeInOut(duration: 0.15), value: hovering)
            .onAppear { syncBreathing() }
            .onChange(of: item.status) { syncBreathing() }
    }

    /// Start the repeating pulse when waiting; stop it otherwise. Called on appear
    /// and whenever status flips, so a completed->waiting change while the tab is
    /// already on screen still animates.
    private func syncBreathing() {
        if isWaiting {
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                breathe = true
            }
        } else {
            breathe = false
        }
    }

    /// The main working tree shows a "home" icon; named worktrees show the
    /// branch's initial letter. Decorative: the enclosing Button carries the
    /// spelled-out label, so this must not be read on its own.
    @ViewBuilder private func glyph(_ identity: ReminderIdentity) -> some View {
        if identity.isMainLine {
            Image(systemName: "house.fill")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
        } else {
            Text(identity.worktreeGlyph)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .accessibilityHidden(true)
        }
    }
}

/// The small square "close all" tab pinned below the strip. Neutral gray so it
/// reads as a control, not a project.
private struct CloserTabView: View {
    @State private var hovering = false

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 8, bottomLeadingRadius: 8,
            bottomTrailingRadius: 0, topTrailingRadius: 0
        )
    }

    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .accessibilityHidden(true) // the enclosing Button carries the label
            .foregroundStyle(.white.opacity(hovering ? 1 : 0.75))
            .frame(width: EdgeGeometry.closerSize, height: EdgeGeometry.closerSize)
            .background(Color.black.opacity(hovering ? 0.55 : 0.35))
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(hovering ? 0.5 : 0.12), lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}
