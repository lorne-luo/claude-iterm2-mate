import AppKit
import SwiftUI

@MainActor
protocol ToastPanelProtocol: AnyObject {
    func show(item: ReminderItem, on visible: CGRect, showsMinimize: Bool,
              onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
              onMinimize: @escaping () -> Void, onClose: @escaping () -> Void)
    func hide()
}

@MainActor
final class ToastPanel: ToastPanelProtocol {
    private var panel: NSPanel?

    static let width: CGFloat = 440
    static let minHeight: CGFloat = 56
    /// Caps a long (6-line) message; short ones size down naturally.
    static let maxHeight: CGFloat = 240

    func show(item: ReminderItem, on visible: CGRect, showsMinimize: Bool,
              onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
              onMinimize: @escaping () -> Void, onClose: @escaping () -> Void) {
        hide()
        let height = Self.fittingHeight(item: item)
        let frame = EdgeGeometry.toastFrame(size: CGSize(width: Self.width, height: height), visible: visible)
        // canBecomeKey so the SwiftUI tap gesture receives the click.
        let panel = PanelFactory.makePanel(frame: frame, canBecomeKey: true)
        panel.contentView = FirstMouseHostingView(rootView: ToastView(
            item: item,
            onTap: { [weak self] in
                self?.dismiss()
                onClick()
            },
            onHover: onHover,
            showsMinimize: showsMinimize,
            onMinimize: onMinimize,
            onClose: onClose
        ))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Natural height of the toast card at `width`, clamped to [min, max], so a
    /// short message doesn't leave a tall blank card. Mirrors DetailPanel.
    private static func fittingHeight(item: ReminderItem) -> CGFloat {
        let probe = NSHostingView(rootView: ToastView(item: item).frame(width: width))
        probe.layoutSubtreeIfNeeded()
        return min(max(probe.fittingSize.height, minHeight), maxHeight)
    }

    /// Immediate close (no fly-in) — used when the toast is clicked, since we're
    /// jumping to the pane rather than queuing a tab.
    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
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
    var onTap: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var showsMinimize: Bool = false
    var onMinimize: () -> Void = {}
    var onClose: () -> Void = {}

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
            // Top-right controls; laid out (not overlaid) so the text reserves
            // room for them and never runs underneath.
            HStack(spacing: 6) {
                if showsMinimize {
                    iconButton("minus", label: "Minimize to tab", action: onMinimize)
                }
                iconButton("xmark", label: "Close", action: onClose)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
        .padding(8) // inset within the panel so the shadow is not clipped
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover(perform: onHover)
    }
}
