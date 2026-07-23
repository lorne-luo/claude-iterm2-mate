import SwiftUI

/// The 8 categorical project colors, in a fixed order. The order is a stable
/// contract: `ColorAssigner`/`ReminderIdentity` hash a project to an index, so
/// reordering would reassign every project's color. Tabs render the bright
/// `rgb` values; iTerm2 pane backgrounds render dark variants of the same hue
/// (see `backgroundComponents`). The glyph foreground flips black/white by
/// background luminance so it always contrasts.
///
/// The names originate from Claude Code's `/color` palette (the old prompt-bar
/// sync); they no longer drive any injection but document each slot's hue.
enum ReminderPalette {
    /// Human-readable hue names; `names[i]` corresponds to `rgb[i]`.
    static let names = ["red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan"]

    /// sRGB components in 0...1. Count must equal `ReminderIdentity.paletteCount`.
    /// Dark-theme hex: red #ff5858, blue #57c7ff, green #50fa7b, yellow #f1fa8c,
    /// purple #bd93f9, orange #ffb86c, pink #ff79c6, cyan #8be9fd.
    private static let rgb: [(r: Double, g: Double, b: Double)] = [
        (1.000, 0.345, 0.345), // red
        (0.341, 0.780, 1.000), // blue
        (0.314, 0.980, 0.482), // green
        (0.945, 0.980, 0.549), // yellow
        (0.741, 0.576, 0.976), // purple
        (1.000, 0.722, 0.424), // orange
        (1.000, 0.475, 0.776), // pink
        (0.545, 0.914, 0.992), // cyan
    ]

    static let colors: [Color] = rgb.map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b) }

    // MARK: - Pane background variants
    //
    // A project's iTerm2 pane background uses a DARK variant of its bright tab
    // hue: the bright palette color is blended toward a near-black anchor until
    // its luminance hits a target, so every hue lands at the SAME (readable) dark
    // luminance while keeping its color. Worktree siblings (same slot) separate
    // by `shade` level, which nudges the target luminance up a little per level.
    // A luminance target (not a fixed blend) is used because the raw palette
    // spans very different brightnesses (yellow ~0.94 vs blue ~0.55); a fixed
    // blend would leave yellow/green too light for legible foreground text.

    /// Near-black anchor the hue is blended toward for pane backgrounds.
    private static let bgAnchor: (r: Double, g: Double, b: Double) = (0.11, 0.11, 0.13)
    private static let bgAnchorLum = 0.2126 * 0.11 + 0.7152 * 0.11 + 0.0722 * 0.13
    /// Target relative luminance at shade 0 (darkest). ~0.16 keeps light text
    /// clearly readable (the spike's comfortable `#2E4057` is ~0.24).
    private static let bgTargetLum0 = 0.16
    /// Each worktree shade level lifts the target luminance this much.
    private static let bgTargetStep = 0.04
    /// Cap so a stray high level can never push a background out of the dark zone.
    private static let bgTargetCap = 0.24

    /// sRGB components (0...1) for a pane background at `index`, `shade` level.
    /// The blend toward the anchor is linear, so luminance is linear in the blend
    /// fraction `t`; we solve `t` directly to hit the target luminance.
    static func backgroundComponents(at index: Int, shade level: Int = 0) -> (r: Double, g: Double, b: Double) {
        let base = rgb[wrap(index)]
        let target = min(bgTargetCap, bgTargetLum0 + bgTargetStep * Double(max(0, level)))
        let baseLum = 0.2126 * base.r + 0.7152 * base.g + 0.0722 * base.b
        let denom = baseLum - bgAnchorLum
        let t = denom > 0.0001 ? min(1, max(0, (baseLum - target) / denom)) : 1
        return (
            base.r * (1 - t) + bgAnchor.r * t,
            base.g * (1 - t) + bgAnchor.g * t,
            base.b * (1 - t) + bgAnchor.b * t
        )
    }

    /// `RRGGBB` hex for a pane background, for the coloring script.
    static func backgroundHex(at index: Int, shade level: Int = 0) -> String {
        let c = backgroundComponents(at: index, shade: level)
        let to255 = { (v: Double) in Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", to255(c.r), to255(c.g), to255(c.b))
    }

    /// Relative luminance (WCAG coefficients) of a pane background variant —
    /// used by tests to guarantee light text stays readable.
    static func backgroundLuminance(at index: Int, shade level: Int = 0) -> Double {
        let c = backgroundComponents(at: index, shade: level)
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    /// Attention accent for a **waiting** tab/toast: bright white. Deliberately
    /// NOT a palette slot — it must not shift `paletteCount` or the `/color` name
    /// mapping. Rendered as a breathing glow on top of the project color.
    static let waitingAccent = Color.white

    /// Glyph flips to black once the background luminance rises above this.
    static let glyphLuminanceThreshold = 0.6

    /// Fraction blended toward white per worktree level. Level 0 is the main
    /// working tree (base color); each additional linked worktree of the same
    /// repo gets the next, lighter tint so siblings are distinguishable while
    /// staying clearly the same hue. Levels beyond the table clamp to the last.
    private static let lightenFactors: [Double] = [0, 0.3, 0.5, 0.65]

    /// Effective sRGB components for a tab: the base palette color, lightened
    /// and desaturated by the worktree `level`.
    static func components(at index: Int, level: Int = 0) -> (r: Double, g: Double, b: Double) {
        let base = rgb[wrap(index)]
        let t = lightenFactors[max(0, min(level, lightenFactors.count - 1))]
        guard t > 0 else { return base }
        return (
            base.r + (1 - base.r) * t,
            base.g + (1 - base.g) * t,
            base.b + (1 - base.b) * t
        )
    }

    static func color(at index: Int, level: Int = 0) -> Color {
        let c = components(at: index, level: level)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
    }

    /// Black on light backgrounds, white on dark ones (WCAG relative-luminance
    /// heuristic), computed against the ACTUAL rendered variant color so the
    /// base and lightened tints each get a legible glyph.
    static func glyphForeground(at index: Int, level: Int = 0) -> Color {
        let c = components(at: index, level: level)
        let luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return luminance > glyphLuminanceThreshold ? .black : .white
    }

    private static func wrap(_ index: Int) -> Int {
        let n = rgb.count
        return ((index % n) + n) % n
    }
}
