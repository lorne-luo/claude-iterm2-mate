import SwiftUI

/// The 8 Claude Code `/color` prompt-bar colors, in the CLI's own order.
/// Sharing the NAME (not the hex) with Claude Code is the sync contract: the
/// app injects `/color <name>` into the session and renders the same name here
/// using its dark-theme (Dracula) hex, so tab and prompt bar read as one color.
/// The glyph foreground flips between black and white by background luminance
/// so it always contrasts.
enum ReminderPalette {
    /// `/color` argument names; `names[i]` corresponds to `rgb[i]`.
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

    /// The `/color` name rendered at a (wrapped) palette index.
    static func colorName(at index: Int) -> String { names[wrap(index)] }

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
