import SwiftUI

/// Interactive answer controls for a single AskUserQuestion question, rendered
/// inside the detail popup and the toast. Option buttons (or checkboxes for
/// multiSelect), a free-text field, and "Chat about this". Emits the chosen
/// answer together with the option count so the caller can build the tty
/// injection sequence.
struct QuestionAnswerView: View {
    let question: NotifyPayload.Question
    var onAnswer: (ItermSendTextAction.Answer, Int) -> Void = { _, _ in }
    var onChat: () -> Void = {}
    /// Fired when the free-text field gains focus. The toast wires this to
    /// `panel.makeKey()` so a passively-shown toast only steals keyboard focus
    /// once the user clicks into the field; the detail panel leaves it a no-op
    /// (it is already key).
    var onEditingBegan: () -> Void = {}

    /// 1-based indices toggled on for a multiSelect question.
    @State private var selected: Set<Int> = []
    @State private var freeText: String = ""
    @FocusState private var textFocused: Bool

    private var optionCount: Int { question.options.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !question.question.isEmpty {
                Text(question.question)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(Array(question.options.enumerated()), id: \.offset) { idx, option in
                optionButton(index: idx + 1, option: option)
            }

            if question.multiSelect {
                Button("Submit") { onAnswer(.multi(selected.sorted()), optionCount) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selected.isEmpty)
            }

            HStack(spacing: 6) {
                TextField("Type your own answer…", text: $freeText)
                    .textFieldStyle(.roundedBorder)
                    .focused($textFocused)
                    .onChange(of: textFocused) { _, focused in
                        if focused { onEditingBegan() }
                    }
                    .onSubmit { submitText() }
                Button("Send") { submitText() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button {
                onChat()
            } label: {
                Label("Chat about this", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submitText() {
        let t = freeText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onAnswer(.text(t), optionCount)
    }

    @ViewBuilder
    private func optionButton(index: Int, option: NotifyPayload.Question.Option) -> some View {
        // One combined VoiceOver label ("label, description") replaces the
        // per-Text reads and the decorative index/checkbox glyph (hidden below).
        let a11yLabel = option.description.isEmpty ? option.label : "\(option.label), \(option.description)"
        if question.multiSelect {
            Button {
                if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
            } label: {
                optionLabel(index: index, option: option, checked: selected.contains(index))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(a11yLabel)
            .accessibilityAddTraits(selected.contains(index) ? .isSelected : [])
        } else {
            Button {
                onAnswer(.option(index), optionCount)
            } label: {
                optionLabel(index: index, option: option, checked: nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(a11yLabel)
        }
    }

    private func optionLabel(index: Int, option: NotifyPayload.Question.Option, checked: Bool?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: checked == nil
                ? "\(index).circle"
                : (checked! ? "checkmark.square.fill" : "square"))
                .font(.system(size: 13))
                .foregroundStyle(.tint)
                .accessibilityHidden(true) // decorative; the Button carries the label + selection trait
            VStack(alignment: .leading, spacing: 1) {
                Text(option.label).font(.system(size: 12, weight: .medium))
                if !option.description.isEmpty {
                    Text(option.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}
