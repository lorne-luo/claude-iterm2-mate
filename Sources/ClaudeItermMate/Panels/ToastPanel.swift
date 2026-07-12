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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("[CC] \(item.projectName)")
                .font(.system(size: 13, weight: .semibold))
            Text(item.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 1))
    }
}
