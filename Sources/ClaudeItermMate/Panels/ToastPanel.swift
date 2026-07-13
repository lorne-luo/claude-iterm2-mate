import AppKit
import SwiftUI

@MainActor
protocol ToastPanelProtocol: AnyObject {
    func show(item: ReminderItem, on visible: CGRect)
    func hide()
}

@MainActor
final class ToastPanel: ToastPanelProtocol {
    private var panel: NSPanel?

    func show(item: ReminderItem, on visible: CGRect) {
        hide()
        let frame = EdgeGeometry.toastFrame(visible: visible)
        let panel = PanelFactory.makePanel(frame: frame, canBecomeKey: false)
        panel.contentViewController = NSHostingController(rootView: ToastView(item: item))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Fly-into-the-tab-strip dismissal: shrink toward the right screen edge
    /// (vertical center, where the strip lives) while fading.
    func hide() {
        guard let panel else { return }
        self.panel = nil
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

    /// Character budget for the toast title at 360pt / 13pt semibold.
    static let titleBudget = 42

    /// `[CC] project · branch` when it fits within `titleBudget`; otherwise the
    /// branch is truncated (with an ellipsis), and dropped entirely if even the
    /// project alone leaves no room.
    static func title(project: String, branch: String?) -> String {
        let base = "[CC] \(project)"
        guard let branch, !branch.isEmpty else { return base }
        let full = "\(base) · \(branch)"
        if full.count <= titleBudget { return full }
        let prefix = "\(base) · "
        let room = titleBudget - prefix.count - 1 // reserve 1 for the ellipsis
        guard room >= 1 else { return base }
        return prefix + branch.prefix(room) + "…"
    }

    var body: some View {
        let identity = item.identity
        HStack(alignment: .top, spacing: 10) {
            // Project-color bar ties the toast to its right-edge tab.
            RoundedRectangle(cornerRadius: 2)
                .fill(ReminderPalette.color(at: identity.colorIndex, worktree: item.isWorktree))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(project: item.projectName, branch: item.branch))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(item.fullMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
        .padding(8) // inset within the panel so the shadow is not clipped
    }
}
