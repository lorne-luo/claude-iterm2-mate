import AppKit
import SwiftUI

@MainActor
final class DetailPanel {
    private var panel: NSPanel?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var mouseInsideDetail = false

    static let showDelay: TimeInterval = 0.5
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
        return f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        let accent = ReminderPalette.color(at: item.identity.colorIndex, worktree: item.isWorktree)
        VStack(spacing: 0) {
            // Header: neutral text on a very light wash of the project color.
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.projectName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(Self.relativeTime(item.timestamp))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let branch = item.branch, !branch.isEmpty {
                    Text("⎇ \(branch)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.15))

            Divider()

            ScrollView {
                Text(item.fullMessage)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(10) // inset within the panel so the shadow is not clipped
        .onHover(perform: onHoverChanged)
    }
}
