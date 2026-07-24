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

    func testPaletteNameOrderIsStable() {
        // The order is a contract: projects hash to an index, so reordering
        // would reassign every project's color.
        XCTAssertEqual(ReminderPalette.names.count, ReminderIdentity.paletteCount)
        XCTAssertEqual(
            ReminderPalette.names,
            ["red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan"]
        )
    }

    func testColorNameMapsSlotToNameAndWraps() {
        for (i, name) in ReminderPalette.names.enumerated() {
            XCTAssertEqual(ReminderPalette.colorName(at: i), name)
        }
        // Out-of-range indices wrap into the palette (negative and overflow).
        let n = ReminderPalette.names.count
        XCTAssertEqual(ReminderPalette.colorName(at: n), ReminderPalette.names[0])
        XCTAssertEqual(ReminderPalette.colorName(at: -1), ReminderPalette.names[n - 1])
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

    // MARK: - Pane background variants

    /// Shade levels a worktree can take (PaneShade.levels = 3 → 0...2).
    private let shades = [0, 1, 2]

    func testBackgroundVariantsAreDarkEnoughForLightText() {
        // Every hue at every shade must land in the readable dark zone so light
        // foreground text stays legible.
        for i in 0..<ReminderIdentity.paletteCount {
            for shade in shades {
                let lum = ReminderPalette.backgroundLuminance(at: i, shade: shade)
                XCTAssertLessThanOrEqual(lum, 0.25, "index \(i) shade \(shade): background too light")
                XCTAssertGreaterThan(lum, 0.10, "index \(i) shade \(shade): background not distinguishable from black")
            }
        }
    }

    func testBackgroundLuminanceHitsTargetAndRisesWithShade() {
        // The luminance-target derivation makes every hue share the same dark
        // luminance at a given shade, and each higher shade is a touch lighter.
        for shade in shades {
            let lums = (0..<ReminderIdentity.paletteCount).map {
                ReminderPalette.backgroundLuminance(at: $0, shade: shade)
            }
            let spread = (lums.max() ?? 0) - (lums.min() ?? 0)
            XCTAssertLessThan(spread, 0.02, "shade \(shade): all hues should share ~the same luminance")
        }
        for i in 0..<ReminderIdentity.paletteCount {
            XCTAssertGreaterThan(
                ReminderPalette.backgroundLuminance(at: i, shade: 1),
                ReminderPalette.backgroundLuminance(at: i, shade: 0),
                "index \(i): shade 1 must be lighter than shade 0"
            )
        }
    }

    func testBackgroundPreservesHue() {
        // The dominant channel of the dark background matches its bright source,
        // so the pane reads as the same color as the tab.
        func argmax(_ c: (r: Double, g: Double, b: Double)) -> Int {
            if c.r >= c.g && c.r >= c.b { return 0 }
            return c.g >= c.b ? 1 : 2
        }
        for i in 0..<ReminderIdentity.paletteCount {
            let bright = ReminderPalette.components(at: i, level: 0)
            for shade in shades {
                let bg = ReminderPalette.backgroundComponents(at: i, shade: shade)
                XCTAssertEqual(argmax(bg), argmax(bright), "index \(i) shade \(shade): hue drifted")
            }
        }
    }

    func testBackgroundHexFormat() {
        for i in 0..<ReminderIdentity.paletteCount {
            let hex = ReminderPalette.backgroundHex(at: i, shade: 0)
            XCTAssertEqual(hex.count, 6, "index \(i): hex must be RRGGBB")
            XCTAssertNil(hex.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789ABCDEF").inverted),
                         "index \(i): hex must be uppercase hex digits")
        }
    }

    func testBackgroundComponentsStayInGamut() {
        for i in 0..<ReminderIdentity.paletteCount {
            for shade in [0, 1, 2, 9] { // 9 exercises the target cap
                let c = ReminderPalette.backgroundComponents(at: i, shade: shade)
                for v in [c.r, c.g, c.b] {
                    XCTAssertGreaterThanOrEqual(v, 0)
                    XCTAssertLessThanOrEqual(v, 1)
                }
            }
        }
    }
}
