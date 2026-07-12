import AppKit
import SwiftUI

@MainActor
final class DetailPanel {
    private var panel: NSPanel?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var mouseInsideDetail = false

    static let showDelay: TimeInterval = 0.3
    static let hideGrace: TimeInterval = 0.2
    static let size = CGSize(width: 420, height: 520)

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
        let frame = EdgeGeometry.detailFrame(anchoring: tabFrame, size: Self.size, visible: visible)
        let panel = self.panel ?? PanelFactory.makePanel(frame: frame, canBecomeKey: true)
        self.panel = panel
        panel.contentViewController = NSHostingController(rootView: DetailView(
            item: item,
            onHoverChanged: { [weak self] inside in
                self?.mouseInsideDetail = inside
                if inside { self?.hideWork?.cancel() } else { self?.scheduleHide() }
            }
        ))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
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
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.projectName)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(Date(timeIntervalSince1970: item.timestamp / 1000), style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                Text(item.fullMessage)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1))
        .onHover(perform: onHoverChanged)
    }
}
