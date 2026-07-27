import XCTest
@testable import ClaudeItermMate

/// The expand chevron's visibility rule. The height inputs come from an offscreen
/// `NSHostingView` probe, which cannot run headless — only the comparison is tested.
final class ToastExpandTests: XCTestCase {
    func testNoToggleWhenNothingIsTruncated() {
        // Message fits within the 10-line limit: expanding it changes nothing.
        XCTAssertFalse(ToastPanel.needsExpandToggle(collapsed: 200, expanded: 200))
    }

    func testToggleWhenExpandingRevealsMore() {
        XCTAssertTrue(ToastPanel.needsExpandToggle(collapsed: 200, expanded: 480))
    }

    func testNoToggleWhenBothStatesArePinnedToMaxHeight() {
        // Already at the cap collapsed, so expanding cannot show anything new.
        let cap = ToastPanel.maxHeight
        XCTAssertFalse(ToastPanel.needsExpandToggle(collapsed: cap, expanded: cap))
    }

    func testSubPointGrowthIsWithinTolerance() {
        // Layout/float jitter must not sprout a chevron on an untruncated message.
        XCTAssertFalse(ToastPanel.needsExpandToggle(collapsed: 200, expanded: 200.5))
    }
}
