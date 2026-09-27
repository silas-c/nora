import NoraCore
import SwiftUI

struct TextRequestBar: View {
    @Bindable var model: AppModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale

    var body: some View {
        let enabled = model.interaction.acceptsInput
        let hasText = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(spacing: 12 * scale) {
            Image(systemName: "keyboard")
                .font(.system(size: 18 * scale))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                TextField("Type a request", text: $model.draft,
                          prompt: Text("Type a command here…").foregroundStyle(.secondary))
                    .textFieldStyle(.plain)
                    .font(.nora(15, scale: scale))
                    .focused(focus, equals: .textField)
                    .onSubmit { model.submitDraft() }
                    .accessibilityLabel("Type a request")
                    .accessibilityHint("Press Return to send")
            Button { model.submitDraft() } label: {
                Image(systemName: "return")
                    .font(.system(size: 18 * scale, weight: .medium))
                    .frame(width: 28 * scale, height: 32 * scale)
            }
            .buttonStyle(.plain)
            .disabled(!enabled || !hasText)
            .accessibilityLabel("Send request")
        }
        .padding(.horizontal, 14 * scale)
        .frame(minHeight: 48 * scale)
        .modifier(NoraGlass(shape: RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)))
        .onChange(of: model.draft) { _, value in
            if value.count > AppModel.maximumTextLength { model.draft = String(value.prefix(AppModel.maximumTextLength)) }
        }
    }
}

struct VoiceButton: View {
    let model: AppModel
    @Environment(\.noraScale) private var scale

    var body: some View {
        let voice = model.voice
        let transcribing = voice.state == .transcribing
        let enabled = voice.isBusy || model.interaction.acceptsInput
        Button { model.toggleVoice() } label: {
            Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 27 * scale, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 68 * scale, height: 68 * scale)
                .background(Circle().fill(LinearGradient(colors: voice.isListening
                    ? [Color.red.opacity(0.7), Color.red]
                    : [Color(red: 0.42, green: 0.70, blue: 1), Color(red: 0.06, green: 0.42, blue: 1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
                .shadow(color: (voice.isListening ? Color.red : Color.blue).opacity(0.5), radius: 13 * scale)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || transcribing)
        .accessibilityLabel(voice.isListening ? "Stop listening" : transcribing ? "Transcribing" : "Speak to Nora")
        .accessibilityHint(voice.isListening ? "Stops listening now" : "Nora stops by itself when you pause")
    }
}
