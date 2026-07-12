import AppKit

/// Borderless non-activating floating panel — the keymic-pro recipe.
/// `canBecomeKey: true` panels take key status without activating the app,
/// which SwiftUI buttons inside need in order to receive clicks.
enum PanelFactory {
    static func makePanel(frame: NSRect, canBecomeKey: Bool) -> NSPanel {
        final class KeyablePanel: NSPanel {
            var allowsKey = false
            override var canBecomeKey: Bool { allowsKey }
            override var canBecomeMain: Bool { false }
        }
        let panel = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.allowsKey = canBecomeKey
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}
