import Foundation
import NoraCore
import Observation

/// Preferences, persisted to UserDefaults. `nil` defaults keep previews and snapshots from touching real settings.
@Observable @MainActor
final class Settings {
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored var onScaleChange: (Double) -> Void = { _ in }
    @ObservationIgnored var onSpeechChange: () -> Void = {}

    var scale: Double { didSet { store(scale, "scale"); onScaleChange(scale) } }
    var spokenFeedback: Bool { didSet { store(spokenFeedback, "spokenFeedback") } }
    var useElevenLabs: Bool { didSet { store(useElevenLabs, "useElevenLabs"); onSpeechChange() } }
    var voiceId: String { didSet { store(voiceId, "voiceId"); onSpeechChange() } }
    var speechRate: Double { didSet { store(speechRate, "speechRate"); onSpeechChange() } }
    var scanning: Bool { didSet { store(scanning, "scanning") } }
    var scanInterval: Double { didSet { store(scanInterval, "scanInterval") } }
    var dwell: Bool { didSet { store(dwell, "dwell") } }
    var dwellSeconds: Double { didSet { store(dwellSeconds, "dwellSeconds") } }
    var aliases: [Alias] { didSet { storeAliases() } }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        scale = defaults?.object(forKey: "scale") as? Double ?? 1.0
        spokenFeedback = defaults?.object(forKey: "spokenFeedback") as? Bool ?? true
        useElevenLabs = defaults?.object(forKey: "useElevenLabs") as? Bool ?? true
        voiceId = defaults?.string(forKey: "voiceId") ?? SpeechPhrases.voices[0].id
        speechRate = defaults?.object(forKey: "speechRate") as? Double ?? 1.0
        scanning = defaults?.object(forKey: "scanning") as? Bool ?? false
        scanInterval = defaults?.object(forKey: "scanInterval") as? Double ?? 1.4
        dwell = defaults?.object(forKey: "dwell") as? Bool ?? false
        dwellSeconds = defaults?.object(forKey: "dwellSeconds") as? Double ?? 1.2
        if let data = defaults?.data(forKey: "aliases"), let stored = try? JSONDecoder().decode([Alias].self, from: data) {
            aliases = stored
        } else {
            aliases = [Alias(phrase: "my school thing", intent: "OPEN_SCHOOL"), Alias(phrase: "pictures", intent: "OPEN_PHOTOS")]
        }
    }

    private func store(_ value: Any, _ key: String) {
        defaults?.set(value, forKey: key)
    }

    private func storeAliases() {
        if let data = try? JSONEncoder().encode(aliases) { defaults?.set(data, forKey: "aliases") }
    }
}
