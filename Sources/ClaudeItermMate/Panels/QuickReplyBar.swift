import SwiftUI

/// One canned prompt, sent into the owning pane as if typed and submitted.
/// The list is deliberately fixed and short — this is a "one more nudge" row at
/// the bottom of a reminder, not a scripting surface.
struct QuickReply: Identifiable, Equatable {
    let id: String
    /// SF Symbol shown in the bar; the text itself only appears as a tooltip.
    let symbol: String
    /// Tooltip + VoiceOver label.
    let label: String
    /// Exactly what is typed into the composer before the submit key.
    let text: String

    static let all: [QuickReply] = [
        QuickReply(id: "continue", symbol: "play.fill",
                   label: "Continue", text: "continue"),
        QuickReply(id: "commit", symbol: "arrow.triangle.branch",
                   label: "Commit to git", text: "commit to git"),
        QuickReply(id: "commit-push", symbol: "arrow.up.circle",
                   label: "Commit + push to remote", text: "commit to git and push to remote"),
        QuickReply(id: "commit-push-pr", symbol: "arrow.triangle.pull",
                   label: "Commit + push + open a PR",
                   text: "commit to git and push to remote and create pr with description refined"),
    ]
}

/// The quick-reply icon row pinned to the bottom of a toast / detail popup.
/// Icon-only (the prompt text is the tooltip) so it costs one 28pt row whatever
/// the card's width.
struct QuickReplyBar: View {
    var onQuickReply: (QuickReply) -> Void = { _ in }

    /// The icon currently under the pointer, captioned to the right of the row.
    /// An inline caption rather than only `.help()`: the toast is a
    /// non-activating panel shown for a few seconds, so waiting out AppKit's
    /// tooltip delay is longer than the toast itself lives.
    @State private var hovered: QuickReply?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(QuickReply.all) { reply in
                QuickReplyButton(reply: reply, onHover: { inside in
                    // Only clear on exit if it is still this button's caption:
                    // moving between two icons delivers the enter before the exit.
                    if inside { hovered = reply } else if hovered == reply { hovered = nil }
                }) {
                    onQuickReply(reply)
                }
            }
            // Reserves no room when idle — the row keeps its height either way,
            // so the card never resizes as the pointer crosses it.
            if let hovered {
                Text(hovered.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .contain)
    }
}

/// A compact bordered icon button; hover raises the fill and the icon's opacity.
private struct QuickReplyButton: View {
    let reply: QuickReply
    /// Reported up so the bar can caption the hovered icon.
    let onHover: (Bool) -> Void
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: reply.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(hovering ? 1 : 0.78))
                .frame(width: 32, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.14 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(hovering ? 0.22 : 0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        // .plain keeps the press from bubbling to the card's tap-to-jump gesture,
        // the same reason the minimize/close buttons need it.
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            onHover(inside)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(reply.label)
        .accessibilityLabel(reply.label)
    }
}
