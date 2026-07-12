import SwiftUI

/// Curated 12-color categorical palette for per-project tab backgrounds.
/// Hues are chosen to be mutually distinguishable, brand-neutral, and legible
/// on both light and dark desktops (following dataviz categorical principles —
/// balanced, not random). The glyph foreground flips between black and white
/// by background luminance so it always contrasts.
enum ReminderPalette {
    /// sRGB components in 0...1. Count must equal `ReminderIdentity.paletteCount`.
    private static let rgb: [(r: Double, g: Double, b: Double)] = [
        (0.298, 0.471, 0.659), // blue
        (0.961, 0.522, 0.094), // orange
        (0.894, 0.341, 0.337), // red
        (0.447, 0.718, 0.698), // teal
        (0.329, 0.635, 0.294), // green
        (0.933, 0.792, 0.231), // yellow
        (0.698, 0.475, 0.635), // purple
        (1.000, 0.616, 0.651), // pink
        (0.616, 0.459, 0.365), // brown
        (0.424, 0.773, 0.878), // cyan
        (0.490, 0.357, 0.651), // indigo
        (0.710, 0.651, 0.259), // olive
    ]

    static let colors: [Color] = rgb.map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b) }

    static func color(at index: Int) -> Color {
        colors[wrap(index)]
    }

    /// Black on light backgrounds, white on dark ones (WCAG relative-luminance
    /// heuristic on the raw sRGB components).
    static func glyphForeground(at index: Int) -> Color {
        let c = rgb[wrap(index)]
        let luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return luminance > 0.6 ? .black : .white
    }

    private static func wrap(_ index: Int) -> Int {
        let n = rgb.count
        return ((index % n) + n) % n
    }
}
