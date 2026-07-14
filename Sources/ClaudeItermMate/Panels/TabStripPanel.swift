import AppKit
import SwiftUI

@MainActor
final class TabStripPanel {
    private let store: ReminderStore
    private let onClick: (ReminderItem) -> Void
    private let onHover: (ReminderItem?, CGRect) -> Void
    private let onClearAll: () -> Void
    private var panel: NSPanel?

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
        panel.contentView = FirstMouseHostingView(rootView: TabStripView(
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
        ))
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
                EdgeTabView(item: item)
                    .onTapGesture { onClick(item) }
                    .onHover { inside in
                        onHover(inside ? item : nil, inside ? index : nil)
                    }
            }
            CloserTabView()
                .onTapGesture { onClearAll() }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// Named EdgeTabView to avoid shadowing SwiftUI.TabView.
private struct EdgeTabView: View {
    let item: ReminderItem
    @State private var hovering = false

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 11, bottomLeadingRadius: 11,
            bottomTrailingRadius: 0, topTrailingRadius: 0
        )
    }

    var body: some View {
        let identity = item.identity
        let base = ReminderPalette.color(at: identity.colorIndex, worktree: item.isWorktree)
        glyph(identity)
            .foregroundStyle(ReminderPalette.glyphForeground(at: identity.colorIndex, worktree: item.isWorktree))
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
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    /// The main working tree shows a "home" icon; named worktrees show the
    /// branch's initial letter.
    @ViewBuilder private func glyph(_ identity: ReminderIdentity) -> some View {
        if identity.isMainLine {
            Image(systemName: "house.fill")
                .font(.system(size: 13, weight: .semibold))
        } else {
            Text(identity.worktreeGlyph)
                .font(.system(size: 14, weight: .bold, design: .rounded))
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
