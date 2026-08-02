import SwiftUI

/// The Setup checklist. A pure renderer of `[SetupRow]` — every decision about
/// which rows exist and what they say lives in `SetupRow.rows`, which is where
/// it can be tested.
struct SetupView: View {
    static let width: CGFloat = 520

    let rows: [SetupRow]
    let suppressAtLaunch: Bool
    let onFix: (SetupRow) -> Void
    let onRecheck: () -> Void
    let onClose: () -> Void
    let onSuppressChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Setup")
                    .font(.system(size: 15, weight: .semibold))
                Text("What this app needs in order to actually do anything.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    SetupRowView(row: row, onFix: { onFix(row) })
                    if row.id != rows.last?.id { Divider().padding(.leading, 42) }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Toggle(
                    "Don't show this at launch",
                    isOn: Binding(get: { suppressAtLaunch }, set: onSuppressChanged)
                )
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                // The menu-bar warnings are unaffected — say so, so ticking it
                // does not read as "hide the problem".
                .help("Stops the window from opening by itself. The menu-bar warnings stay.")
                Spacer()
                Button("Recheck", action: onRecheck)
                // The title bar already has a close button, but the launch path
                // orders the window in without activating — so the eye is on the
                // checklist, not the chrome. A footer button next to Recheck is
                // where "I'm done here" is actually looked for.
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: Self.width)
    }
}

private struct SetupRowView: View {
    let row: SetupRow
    let onFix: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                Text(row.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let label = row.fix.label {
                Button(label, action: onFix)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        // The status is carried by a symbol; spell it out for VoiceOver.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(spokenState). \(row.subtitle)")
    }

    private var symbol: String {
        switch row.state {
        case .ok: return "checkmark.circle.fill"
        case .missing: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch row.state {
        case .ok: return .green
        case .missing: return .red
        // Grey, not yellow: we did not find a problem, we failed to look.
        case .unknown: return .secondary
        }
    }

    private var spokenState: String {
        switch row.state {
        case .ok: return "ready"
        case .missing: return "not ready"
        case .unknown: return "cannot be checked"
        }
    }
}
