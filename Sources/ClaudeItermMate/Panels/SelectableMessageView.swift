import AppKit
import SwiftUI

/// The detail popup's message text, hosted in a read-only `NSTextView` instead of
/// a SwiftUI `Text(...).textSelection(.enabled)`.
///
/// Why AppKit: with the SwiftUI modifier the selection *drew* but could never be
/// copied. ⌘C resolves through `performKeyEquivalent` to `copy:` on the key
/// window's first responder, and a SwiftUI selectable `Text` never becomes one —
/// so the keystroke fell through to whatever app was frontmost (iTerm2) and the
/// clipboard came back holding the terminal's selection instead of ours. Verified
/// on this app: key panel alone, key panel + an Edit menu, and key panel + Edit
/// menu + `NSApp.activate` all left the clipboard untouched. An `NSTextView`
/// becomes first responder on click, implements `copy:`, and brings its own
/// right-click → Copy menu.
struct SelectableMessageView: NSViewRepresentable {
    let text: String
    /// Matches the SwiftUI body font this replaced.
    static let fontSize: CGFloat = 12

    func makeNSView(context: Context) -> MessageTextView {
        let view = MessageTextView.make()
        view.string = text
        return view
    }

    func updateNSView(_ view: MessageTextView, context: Context) {
        guard view.string != text else { return }
        view.string = text
        view.invalidateIntrinsicContentSize()
    }
}

/// Read-only text view that reports its laid-out height to SwiftUI and takes
/// focus on click so ⌘C reaches it.
final class MessageTextView: NSTextView {
    /// One configuration shared by `makeNSView` and the sizing tests, so a test
    /// cannot pass against a differently-configured view than the app renders.
    static func make() -> MessageTextView {
        let view = MessageTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textColor = .labelColor
        view.font = .systemFont(ofSize: SelectableMessageView.fontSize)
        // The card, not the text view, owns scrolling and padding.
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        return view
    }

    /// SwiftUI needs a height for the card's layout (and for `DetailPanel`'s
    /// measuring probe); an `NSTextView` outside a scroll view reports none.
    override var intrinsicContentSize: NSSize {
        guard let manager = layoutManager, let container = textContainer else {
            return super.intrinsicContentSize
        }
        manager.ensureLayout(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: manager.usedRect(for: container).height)
    }

    /// The width SwiftUI hands us decides how the text wraps, so the height is
    /// only known after layout.
    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    /// A click on the text must (a) activate the app and (b) make this view the
    /// key window's first responder — both are required before ⌘C resolves to
    /// `copy:`. This is a deliberate focus steal: the popup is passive until the
    /// user clicks into the text, and selecting text you cannot copy is worse.
    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    /// Non-activating panels do not deliver the first click to their content;
    /// without this the click that starts a selection is spent taking focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
