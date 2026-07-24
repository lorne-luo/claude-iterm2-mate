import AppKit
import SwiftUI

/// An `NSHostingView` that delivers the first click to its SwiftUI content even
/// when its window is not key. Without this, a nonactivating panel eats the
/// first click just to become key, so the content only reacts on the second
/// click (the "double-click to act" bug).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless non-activating floating panel — the keymic-pro recipe.
/// `canBecomeKey: true` panels take key status without activating the app,
/// which SwiftUI buttons inside need in order to receive clicks.
enum PanelFactory {
    /// `editable: true` lets the panel become main as well as key, which the
    /// field editor behind a SwiftUI `TextField` needs to accept keyboard input
    /// (the AskUserQuestion answer field). Plain panels never become main so
    /// they cannot steal the app's foreground focus.
    static func makePanel(frame: NSRect, canBecomeKey: Bool, editable: Bool = false) -> NSPanel {
        final class KeyablePanel: NSPanel {
            var allowsKey = false
            var allowsMain = false
            override var canBecomeKey: Bool { allowsKey }
            override var canBecomeMain: Bool { allowsMain }
        }
        let panel = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.allowsKey = canBecomeKey
        panel.allowsMain = editable
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
