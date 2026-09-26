import NoraCore
import SwiftUI

struct TextRequestBar: View {
    @Bindable var model: AppModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale

    var body: some View {
        let enabled = model.interaction.acceptsInput
        let editing = focus.wrappedValue == .textField
        let hasText = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 10 * scale) {
            SectionLabel("Or type it, or say it")
            HStack(alignment: .center, spacing: 10 * scale) {
                TextField("Type a request", text: $model.draft,
                          prompt: Text("Type what you want").foregroundStyle(Color.primary.opacity(0.7)))
                    .textFieldStyle(.plain)
                    .font(.nora(21, .medium, scale: scale))
                    .padding(.horizontal, 14 * scale)
                    .frame(minHeight: 56 * scale)
                    .background(RoundedRectangle(cornerRadius: 14 * scale).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 14 * scale)
                        .strokeBorder(editing ? Color(nsColor: .keyboardFocusIndicatorColor) : Color.primary.opacity(0.6),
                                      lineWidth: (editing ? 3 : 1.5) * scale))
                    .focused(focus, equals: .textField)
                    .onSubmit { model.submitDraft() }
                    .accessibilityLabel("Type a request")
                    .accessibilityHint("Press Return to send. Examples are listed below.")
                ActionButton(title: "Go", symbol: "arrow.right", style: .prominent, enabled: enabled && hasText,
                             hint: "Sends what you typed") { model.submitDraft() }
                VoiceButton(model: model)
            }
            FlowLayout(spacing: 8 * scale) {
                Text("Try:")
                    .font(.nora(16, .bold, scale: scale))
                    .frame(minHeight: 48 * scale)
                ForEach(Vocabulary.examples, id: \.self) { phrase in
                    ActionButton(title: phrase, style: .chip, enabled: enabled, hint: "Sends this request") {
                        model.submitExample(phrase)
                    }
                }
                if model.mode == .mock {
                    ActionButton(title: "Safety demo: delete Downloads", symbol: "exclamationmark.shield.fill", style: .chip, enabled: enabled,
                                 hint: "A practice request that asks you to confirm. No files are touched.") {
                        model.submitExample("Delete everything in Downloads")
                    }
                }
            }
        }
        .onChange(of: model.draft) { _, value in
            if value.count > AppModel.maximumTextLength { model.draft = String(value.prefix(AppModel.maximumTextLength)) }
        }
    }
}

struct VoiceButton: View {
    let model: AppModel

    var body: some View {
        let voice = model.voice
        let transcribing = voice.state == .transcribing
        let enabled = voice.isBusy || model.interaction.acceptsInput
        ActionButton(title: voice.isListening ? "Stop" : transcribing ? "Wait" : "Speak",
                     symbol: voice.isListening ? "stop.fill" : "mic.fill",
                     style: voice.isListening ? .destructive : .neutral,
                     enabled: enabled && !transcribing,
                     hint: voice.isListening ? "Stops listening now" : "Starts listening. Nora stops by itself when you pause.") {
            model.toggleVoice()
        }
    }
}
