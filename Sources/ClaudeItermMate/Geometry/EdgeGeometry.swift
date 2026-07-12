import Foundation

/// Pure frame math for the right-edge tab strip, toast, and detail panels.
/// All rects are in AppKit screen coordinates (y grows upward).
enum EdgeGeometry {
    static let tabWidth: CGFloat = 28
    static let tabHeight: CGFloat = 64
    static let tabSpacing: CGFloat = 8
    static let screenMargin: CGFloat = 12
    static let toastSize = CGSize(width: 360, height: 88)

    static func maxVisibleTabs(visible: CGRect) -> Int {
        let usable = visible.height - 2 * screenMargin
        return max(1, Int((usable + tabSpacing) / (tabHeight + tabSpacing)))
    }

    static func stripFrame(tabCount: Int, visible: CGRect) -> CGRect {
        let count = min(max(tabCount, 0), maxVisibleTabs(visible: visible))
        let height = CGFloat(count) * tabHeight + CGFloat(max(0, count - 1)) * tabSpacing
        let y = min(
            max(visible.midY - height / 2, visible.minY + screenMargin),
            visible.maxY - height - screenMargin
        )
        return CGRect(x: visible.maxX - tabWidth, y: y, width: tabWidth, height: height)
    }

    /// index 0 = top tab (newest); frames are laid out downward from strip top.
    static func tabFrame(index: Int, stripFrame: CGRect) -> CGRect {
        let top = stripFrame.maxY - CGFloat(index) * (tabHeight + tabSpacing)
        return CGRect(x: stripFrame.minX, y: top - tabHeight, width: stripFrame.width, height: tabHeight)
    }

    static func detailFrame(anchoring tabFrame: CGRect, size: CGSize, visible: CGRect) -> CGRect {
        let maxHeight = visible.height - 2 * screenMargin
        let height = min(size.height, maxHeight)
        let y = min(
            max(tabFrame.midY - height / 2, visible.minY + screenMargin),
            visible.maxY - height - screenMargin
        )
        return CGRect(
            x: tabFrame.minX - tabSpacing - size.width,
            y: y,
            width: size.width,
            height: height
        )
    }

    static func toastFrame(visible: CGRect) -> CGRect {
        CGRect(
            x: visible.maxX - screenMargin - toastSize.width,
            y: visible.maxY - screenMargin - toastSize.height,
            width: toastSize.width,
            height: toastSize.height
        )
    }
}
