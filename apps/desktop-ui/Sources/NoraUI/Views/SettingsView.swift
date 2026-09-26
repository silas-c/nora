import NoraCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var keyDraft = ""
    @State private var keyStatus = ""

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Mode") {
                Picker("Mode", selection: Binding(get: { model.mode }, set: { model.switchMode($0) })) {
                    Text("Practice: nothing on this Mac changes").tag(AgentMode.mock)
                    Text("Live: Nora controls this Mac").tag(AgentMode.live)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Size") {
                Picker("Text and button size", selection: $settings.scale) {
                    ForEach([1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                        Text("\(Int(value * 100))%").tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Spoken feedback") {
                Toggle("Say what Nora is doing", isOn: $settings.spokenFeedback)
                Toggle("Use ElevenLabs voices", isOn: $settings.useElevenLabs)
                Picker("Voice", selection: $settings.voiceId) {
                    ForEach(SpeechPhrases.voices) { voice in
                        Text("\(voice.name) (\(voice.description))").tag(voice.id)
                    }
                }
                Slider(value: $settings.speechRate, in: 0.8...1.2, step: 0.05) {
                    Text("Speaking speed")
                } minimumValueLabel: {
                    Text("Slower")
                } maximumValueLabel: {
                    Text("Faster")
                }
                Text("With VoiceOver on, Nora speaks through VoiceOver only, so nothing is said twice.")
                    .font(.callout)
                HStack {
                    SecureField("ElevenLabs API key", text: $keyDraft)
                    Button("Save") {
                        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        keyStatus = KeychainStore.save(trimmed) ? "Saved to your keychain." : "Could not save the key."
                        keyDraft = ""
                        model.speaker.reloadKey()
                        model.speaker.prewarm()
                    }
                    Button("Remove") {
                        KeychainStore.delete()
                        model.speaker.reloadKey()
                        keyStatus = "Removed. Nora uses the Mac voice."
                    }
                }
                Text(speechStatus).font(.callout)
                if !keyStatus.isEmpty { Text(keyStatus).font(.callout) }
                HStack {
                    Button("Test voice") { model.speaker.speak(SpeechPhrases.sample) }
                    Button("Prepare offline phrases") { model.speaker.prewarm() }
                        .disabled(!model.speaker.hasKey || model.speaker.isPrewarming)
                    Button("Check key") { Task { await checkKey() } }
                        .disabled(!model.speaker.hasKey)
                }
            }

            Section("Ways to choose") {
                Toggle("Switch scanning: the highlight moves by itself; press Space (or a switch) to choose",
                       isOn: Binding(get: { settings.scanning }, set: { model.setScanning($0) }))
                Slider(value: $settings.scanInterval, in: 0.6...3.0, step: 0.1) {
                    Text("Time on each item: \(String(format: "%.1f", settings.scanInterval)) s")
                }
                Toggle("Dwell: rest the pointer on a tile to choose it", isOn: $settings.dwell)
                Slider(value: $settings.dwellSeconds, in: 0.6...2.5, step: 0.1) {
                    Text("Dwell time: \(String(format: "%.1f", settings.dwellSeconds)) s")
                }
            }

            Section("Personal words") {
                Text("Your own words for a tile. Typing or saying them works like pressing the tile, and speech recognition listens for them.")
                    .font(.callout)
                ForEach($settings.aliases) { $alias in
                    HStack {
                        TextField("Words", text: $alias.phrase)
                        Picker("Tile", selection: $alias.intent) {
                            ForEach(TileCatalog.all) { tile in Text(tile.title).tag(tile.intent) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        Button {
                            settings.aliases.removeAll { $0.id == alias.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove \(alias.phrase)")
                    }
                }
                Button("Add a personal word") {
                    settings.aliases.append(Alias(phrase: "", intent: TileCatalog.home[0].intent))
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 640)
    }

    private var speechStatus: String {
        if !model.speaker.hasKey { return "No ElevenLabs key: Nora uses the Mac voice. Set ELEVENLABS_API_KEY or paste a key above." }
        let source = KeychainStore.environmentKey != nil ? "from ELEVENLABS_API_KEY" : "from your keychain"
        return "ElevenLabs key \(source). \(model.speaker.cachedCount) of \(model.speaker.knownPhraseCount) phrases ready offline\(model.speaker.isPrewarming ? " (preparing…)" : "")."
    }

    private func checkKey() async {
        guard let key = KeychainStore.elevenLabsKey() else { return }
        do {
            let count = try await ElevenLabsClient(apiKey: key).voiceCount()
            keyStatus = "The key works. \(count) voices available."
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}
