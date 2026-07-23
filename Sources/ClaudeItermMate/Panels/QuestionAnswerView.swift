import SwiftUI

/// Interactive answer controls for a single AskUserQuestion question, rendered
/// inside the detail popup. Option buttons (or checkboxes for multiSelect), a
/// free-text field, and "Chat about this". Emits the chosen answer together
/// with the option count so the caller can build the tty injection sequence.
struct QuestionAnswerView: View {
    let question: NotifyPayload.Question
    var onAnswer: (ItermSendTextAction.Answer, Int) -> Void = { _, _ in }
    var onChat: () -> Void = {}

    /// 1-based indices toggled on for a multiSelect question.
    @State private var selected: Set<Int> = []
    @State private var freeText: String = ""

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
        if question.multiSelect {
            Button {
                if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
            } label: {
                optionLabel(index: index, option: option, checked: selected.contains(index))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                onAnswer(.option(index), optionCount)
            } label: {
                optionLabel(index: index, option: option, checked: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func optionLabel(index: Int, option: NotifyPayload.Question.Option, checked: Bool?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: checked == nil
                ? "\(index).circle"
                : (checked! ? "checkmark.square.fill" : "square"))
                .font(.system(size: 13))
                .foregroundStyle(.tint)
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
