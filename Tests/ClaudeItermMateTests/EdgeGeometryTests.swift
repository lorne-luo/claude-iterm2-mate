import XCTest
@testable import ClaudeItermMate

final class EdgeGeometryTests: XCTestCase {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testStripFrameHugsRightEdgeAndCenters() {
        let f = EdgeGeometry.stripFrame(tabCount: 2, visible: visible)
        XCTAssertEqual(f.maxX, visible.maxX)
        XCTAssertEqual(f.width, EdgeGeometry.tabWidth)
        XCTAssertEqual(f.height, 2 * EdgeGeometry.tabHeight + EdgeGeometry.tabSpacing)
        XCTAssertEqual(f.midY, visible.midY, accuracy: 0.5)
    }

    func testStripFrameWithCloserAddsCloserHeight() {
        let without = EdgeGeometry.stripFrame(tabCount: 2, hasCloser: false, visible: visible)
        let with = EdgeGeometry.stripFrame(tabCount: 2, hasCloser: true, visible: visible)
        XCTAssertEqual(with.height - without.height, EdgeGeometry.closerSize + EdgeGeometry.tabSpacing, accuracy: 0.01)
        XCTAssertEqual(with.width, EdgeGeometry.tabWidth)
    }

    func testStripFrameClampsToVisibleHeight() {
        let f = EdgeGeometry.stripFrame(tabCount: 100, visible: visible)
        XCTAssertGreaterThanOrEqual(f.minY, visible.minY + EdgeGeometry.screenMargin)
        XCTAssertLessThanOrEqual(f.maxY, visible.maxY - EdgeGeometry.screenMargin)
    }

    func testMaxVisibleTabs() {
        let n = EdgeGeometry.maxVisibleTabs(visible: visible)
        let usable = visible.height - 2 * EdgeGeometry.screenMargin
        let fits = CGFloat(n) * EdgeGeometry.tabHeight + CGFloat(n - 1) * EdgeGeometry.tabSpacing
        XCTAssertLessThanOrEqual(fits, usable)
        let oneMore = fits + EdgeGeometry.tabSpacing + EdgeGeometry.tabHeight
        XCTAssertGreaterThan(oneMore, usable)
    }

    func testTabFrameIndexZeroIsTopTab() {
        let strip = EdgeGeometry.stripFrame(tabCount: 3, visible: visible)
        let top = EdgeGeometry.tabFrame(index: 0, stripFrame: strip)
        let below = EdgeGeometry.tabFrame(index: 1, stripFrame: strip)
        XCTAssertEqual(top.maxY, strip.maxY)
        XCTAssertEqual(top.maxY - below.maxY, EdgeGeometry.tabHeight + EdgeGeometry.tabSpacing)
    }

    func testDetailFrameSitsLeftOfTabAndStaysOnScreen() {
        let strip = EdgeGeometry.stripFrame(tabCount: 1, visible: visible)
        let tab = EdgeGeometry.tabFrame(index: 0, stripFrame: strip)
        let f = EdgeGeometry.detailFrame(anchoring: tab, size: CGSize(width: 420, height: 800), visible: visible)
        XCTAssertEqual(f.maxX, tab.minX - EdgeGeometry.tabSpacing)
        XCTAssertGreaterThanOrEqual(f.minY, visible.minY + EdgeGeometry.screenMargin)
        XCTAssertLessThanOrEqual(f.maxY, visible.maxY - EdgeGeometry.screenMargin)
    }

    func testToastFrameIsTopRight() {
        let f = EdgeGeometry.toastFrame(visible: visible)
        XCTAssertEqual(f.maxX, visible.maxX - EdgeGeometry.screenMargin)
        XCTAssertEqual(f.maxY, visible.maxY - EdgeGeometry.screenMargin)
        XCTAssertEqual(f.size, EdgeGeometry.toastSize)
    }
}
