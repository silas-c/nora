import NoraCore
import SwiftUI

struct TextRequestBar: View {
    @Bindable var model: AppModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale
    @State private var showsPracticeTools = false

    var body: some View {
        let enabled = model.interaction.acceptsInput
        let hasText = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 9 * scale) {
            SectionLabel("Ask Nora")
            HStack(alignment: .center, spacing: 10 * scale) {
                TextField("Type a request", text: $model.draft,
                          prompt: Text("Type what you want").foregroundStyle(Color.primary.opacity(0.7)))
                    .textFieldStyle(.roundedBorder)
                    .font(.nora(16, scale: scale))
                    .frame(minHeight: 48 * scale)
                    .focused(focus, equals: .textField)
                    .onSubmit { model.submitDraft() }
                    .accessibilityLabel("Type a request")
                    .accessibilityHint("Press Return to send. Examples are listed below.")
                ActionButton(title: "Go", symbol: "arrow.right", style: .prominent, enabled: enabled && hasText,
                             hint: "Sends what you typed") { model.submitDraft() }
                VoiceButton(model: model)
            }
            FlowLayout(spacing: 6 * scale) {
                Text("Try:")
                    .font(.nora(13, .medium, scale: scale))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 38 * scale)
                ForEach(Vocabulary.examples, id: \.self) { phrase in
                    ActionButton(title: phrase, style: .chip, enabled: enabled, hint: "Sends this request") {
                        model.submitExample(phrase)
                    }
                }
            }
            if model.mode == .mock {
                DisclosureGroup("Practice tools", isExpanded: $showsPracticeTools) {
                    ActionButton(title: "Safety demo: delete Downloads", symbol: "exclamationmark.shield.fill", style: .chip, enabled: enabled,
                                 hint: "A practice request that asks you to confirm. No files are touched.") {
                        model.submitExample("Delete everything in Downloads")
                    }
                    .padding(.top, 6 * scale)
                }
                .font(.nora(13, .medium, scale: scale))
                .foregroundStyle(.secondary)
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
