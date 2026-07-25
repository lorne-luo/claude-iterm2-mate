import SwiftUI

/// Compact usage meters — one thin bar per rolling window (5h / 7d) — for the
/// toast title row and the detail header, replacing the old `5h N% · 7d N%`
/// text: bar length shows how much of the window is spent, tint how urgent it
/// is (`UsageLevel`). Pure presentation: it takes a decoded snapshot, never the
/// service, so it renders identically in a measuring probe.
struct UsageBadgeView: View {
    let snapshot: UsageSnapshot
    /// Show the numeric percent after each bar. Off in the toast's title row,
    /// which competes with the project · branch title for width.
    var showsPercent: Bool = true

    static let barWidth: CGFloat = 30
    static let barHeight: CGFloat = 3

    var body: some View {
        HStack(spacing: 8) {
            if let fiveHour = snapshot.fiveHour {
                meter(fiveHour, label: "5h")
            }
            if let weekly = snapshot.weekly {
                meter(weekly, label: "7d")
            }
        }
        // One combined read ("5h 4% · 7d 66%") instead of four disjoint fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.badgeText ?? "")
    }

    private func meter(_ window: UsageWindow, label: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Capsule()
                .fill(.secondary.opacity(0.22))
                .frame(width: Self.barWidth, height: Self.barHeight)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Self.tint(window.level))
                        .frame(width: Self.fillWidth(window.utilization), height: Self.barHeight)
                        .animation(.easeOut(duration: 0.25), value: window.utilization)
                }
            if showsPercent {
                Text("\(window.utilization)%")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    /// Filled length for a utilization. A non-zero utilization always draws at
    /// least a round dot (`barHeight` wide) — at 30pt wide, 5% would otherwise be
    /// 1.5pt and read as an empty track.
    static func fillWidth(_ utilization: Int) -> CGFloat {
        guard utilization > 0 else { return 0 }
        return max(barHeight, barWidth * CGFloat(utilization) / 100)
    }

    static func tint(_ level: UsageLevel) -> Color {
        switch level {
        case .ok: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}
