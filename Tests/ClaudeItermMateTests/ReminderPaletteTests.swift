import SwiftUI
import XCTest
@testable import ClaudeItermMate

final class ReminderPaletteTests: XCTestCase {
    /// Perceived lightness (relative luminance) — rises when blending toward white.
    private func lightness(_ c: (r: Double, g: Double, b: Double)) -> Double {
        0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    private func saturation(_ c: (r: Double, g: Double, b: Double)) -> Double {
        let hi = max(c.r, c.g, c.b)
        let lo = min(c.r, c.g, c.b)
        return hi == 0 ? 0 : (hi - lo) / hi
    }

    func testWorktreeVariantIsLighterAndLessSaturated() {
        for i in 0..<ReminderIdentity.paletteCount {
            let base = ReminderPalette.components(at: i, worktree: false)
            let wt = ReminderPalette.components(at: i, worktree: true)
            XCTAssertGreaterThan(lightness(wt), lightness(base), "index \(i): worktree lighter")
            XCTAssertLessThan(saturation(wt), saturation(base), "index \(i): worktree less saturated")
        }
    }

    func testGlyphForegroundMatchesActualRenderedColor() {
        for i in 0..<ReminderIdentity.paletteCount {
            for worktree in [false, true] {
                let c = ReminderPalette.components(at: i, worktree: worktree)
                let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
                let expected: Color = lum > ReminderPalette.glyphLuminanceThreshold ? .black : .white
                XCTAssertEqual(
                    ReminderPalette.glyphForeground(at: i, worktree: worktree), expected,
                    "index \(i) worktree=\(worktree): foreground must follow the actual variant color"
                )
            }
        }
    }

    func testComponentsStayInGamut() {
        for i in 0..<ReminderIdentity.paletteCount {
            for worktree in [false, true] {
                let c = ReminderPalette.components(at: i, worktree: worktree)
                for v in [c.r, c.g, c.b] {
                    XCTAssertGreaterThanOrEqual(v, 0)
                    XCTAssertLessThanOrEqual(v, 1)
                }
            }
        }
    }
}
