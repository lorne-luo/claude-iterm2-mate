import AppKit
import XCTest
@testable import ClaudeItermMate

/// The detail popup's message is an `NSTextView` (so a selection can actually be
/// copied), which means the card's height now comes from `intrinsicContentSize`
/// instead of SwiftUI's own text layout. These cover that height: a text view
/// outside a scroll view reports no intrinsic height by default, and a zero would
/// collapse the popup to `minHeight` with the message clipped away.
@MainActor
final class SelectableMessageViewTests: XCTestCase {
    private func height(_ text: String, width: CGFloat = 488) -> CGFloat {
        let view = MessageTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        view.string = text
        view.layoutSubtreeIfNeeded()
        return view.intrinsicContentSize.height
    }

    func testOneLineHasANonZeroHeight() {
        XCTAssertGreaterThan(height("one line"), 0)
    }

    func testHeightGrowsWithTheLineCount() {
        let one = height("line 1")
        let twenty = height((1...20).map { "line \($0)" }.joined(separator: "\n"))
        XCTAssertGreaterThan(twenty, one * 10, "20 lines must measure far taller than 1")
    }

    /// The container tracks the view's width, so the same text wraps to more
    /// lines — and a taller box — in a narrower card.
    func testNarrowerWidthWrapsTaller() {
        let text = String(repeating: "wrapping probe text ", count: 20)
        XCTAssertGreaterThan(height(text, width: 200), height(text, width: 488))
    }

    func testWidthIsLeftToSwiftUI() {
        let view = MessageTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 10)
        view.string = "probe"
        XCTAssertEqual(view.intrinsicContentSize.width, NSView.noIntrinsicMetric)
    }
}
