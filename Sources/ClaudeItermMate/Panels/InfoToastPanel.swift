import AppKit
import SwiftUI

/// A lightweight, self-dismissing toast for a plain informational message
/// (e.g. the hook-install confirmation). Unlike `ToastPanel` it is not bound to
/// a `ReminderItem` — just a title + message card in the top-right corner,
/// faded in and auto-hidden after `duration`.
@MainActor
final class InfoToastPanel {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    static let width: CGFloat = 360

    func show(title: String, message: String, duration: TimeInterval = 4) {
        hide()
        let root = InfoToastView(title: title, message: message)
        let visible = NSScreen.main?.visibleFrame ?? .zero
        let height = Self.fittingHeight(root)
        let frame = EdgeGeometry.toastFrame(size: CGSize(width: Self.width, height: height), visible: visible)
        // No interaction needed — it dismisses itself — so it never becomes key.
        let panel = PanelFactory.makePanel(frame: frame, canBecomeKey: false)
        panel.contentView = NSHostingView(rootView: root)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        dismissWork?.cancel()
        dismissWork = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    /// Natural height of the card at `width`, so a one-line message doesn't leave
    /// a tall blank panel. Mirrors ToastPanel.fittingHeight.
    private static func fittingHeight(_ root: InfoToastView) -> CGFloat {
        let probe = NSHostingView(rootView: root.frame(width: width))
        probe.layoutSubtreeIfNeeded()
        return probe.fittingSize.height
    }
}

struct InfoToastView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
        .padding(8) // inset within the panel so the shadow is not clipped
    }
}
