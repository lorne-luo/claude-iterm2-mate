import SwiftUI
import XCTest
@testable import ClaudeItermMate

final class ReminderPaletteTests: XCTestCase {
    /// Worktree lighten levels exercised by tests: base + the distinct tints.
    private let levels = [0, 1, 2, 3]

    /// Perceived lightness (relative luminance) — rises when blending toward white.
    private func lightness(_ c: (r: Double, g: Double, b: Double)) -> Double {
        0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    private func saturation(_ c: (r: Double, g: Double, b: Double)) -> Double {
        let hi = max(c.r, c.g, c.b)
        let lo = min(c.r, c.g, c.b)
        return hi == 0 ? 0 : (hi - lo) / hi
    }

    func testPaletteMatchesClaudeCodeColorNames() {
        XCTAssertEqual(ReminderPalette.names.count, ReminderIdentity.paletteCount)
        XCTAssertEqual(
            ReminderPalette.names,
            ["red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan"]
        )
        XCTAssertEqual(ReminderPalette.colorName(at: 0), "red")
        XCTAssertEqual(ReminderPalette.colorName(at: 8), "red") // wraps
        XCTAssertEqual(ReminderPalette.colorName(at: -1), "cyan") // wraps negative
    }

    func testEachLevelIsLighterAndLessSaturatedThanThePrevious() {
        for i in 0..<ReminderIdentity.paletteCount {
            for level in 1...3 {
                let prev = ReminderPalette.components(at: i, level: level - 1)
                let cur = ReminderPalette.components(at: i, level: level)
                XCTAssertGreaterThan(lightness(cur), lightness(prev), "index \(i) level \(level): lighter")
                XCTAssertLessThan(saturation(cur), saturation(prev), "index \(i) level \(level): less saturated")
            }
        }
    }

    func testLevelsBeyondTableClampToLast() {
        for i in 0..<ReminderIdentity.paletteCount {
            let last = ReminderPalette.components(at: i, level: 3)
            let beyond = ReminderPalette.components(at: i, level: 9)
            XCTAssertEqual(last.r, beyond.r)
            XCTAssertEqual(last.g, beyond.g)
            XCTAssertEqual(last.b, beyond.b)
        }
    }

    func testGlyphForegroundMatchesActualRenderedColor() {
        for i in 0..<ReminderIdentity.paletteCount {
            for level in levels {
                let c = ReminderPalette.components(at: i, level: level)
                let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
                let expected: Color = lum > ReminderPalette.glyphLuminanceThreshold ? .black : .white
                XCTAssertEqual(
                    ReminderPalette.glyphForeground(at: i, level: level), expected,
                    "index \(i) level \(level): foreground must follow the actual variant color"
                )
            }
        }
    }

    func testComponentsStayInGamut() {
        for i in 0..<ReminderIdentity.paletteCount {
            for level in levels {
                let c = ReminderPalette.components(at: i, level: level)
                for v in [c.r, c.g, c.b] {
                    XCTAssertGreaterThanOrEqual(v, 0)
                    XCTAssertLessThanOrEqual(v, 1)
                }
            }
        }
    }
}
