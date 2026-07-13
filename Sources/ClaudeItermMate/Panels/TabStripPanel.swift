import AppKit
import SwiftUI

@MainActor
final class TabStripPanel {
    private let store: ReminderStore
    private let onClick: (ReminderItem) -> Void
    private let onHover: (ReminderItem?, CGRect) -> Void
    private var panel: NSPanel?

    init(
        store: ReminderStore,
        onClick: @escaping (ReminderItem) -> Void,
        onHover: @escaping (ReminderItem?, CGRect) -> Void
    ) {
        self.store = store
        self.onClick = onClick
        self.onHover = onHover
        observe()
    }

    /// Re-render on every store mutation via Observation's onChange hook.
    private func observe() {
        withObservationTracking {
            _ = store.items
        } onChange: { [weak self] in
            Task { @MainActor in
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
        let frame = EdgeGeometry.stripFrame(tabCount: queued.count, visible: visible)
        let panel = self.panel ?? Self.makeStripPanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.contentViewController = NSHostingController(rootView: TabStripView(
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
            }
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

    var body: some View {
        VStack(spacing: EdgeGeometry.tabSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                EdgeTabView(item: item)
                    .onTapGesture { onClick(item) }
                    .onHover { inside in
                        onHover(inside ? item : nil, inside ? index : nil)
                    }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// Named EdgeTabView to avoid shadowing SwiftUI.TabView.
private struct EdgeTabView: View {
    let item: ReminderItem

    var body: some View {
        let identity = item.identity
        Text(identity.worktreeGlyph)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(ReminderPalette.glyphForeground(at: identity.colorIndex, worktree: item.isWorktree))
            .frame(width: EdgeGeometry.tabWidth, height: EdgeGeometry.tabHeight)
            .background(ReminderPalette.color(at: identity.colorIndex, worktree: item.isWorktree), in: UnevenRoundedRectangle(
                topLeadingRadius: 10, bottomLeadingRadius: 10,
                bottomTrailingRadius: 0, topTrailingRadius: 0
            ))
            .contentShape(Rectangle())
    }
}
