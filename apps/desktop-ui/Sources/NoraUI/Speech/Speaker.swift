import AppKit
import AVFoundation
import NoraCore
import Observation

/// Spoken feedback. Known phrases play from a local ElevenLabs cache with no network wait;
/// anything else is synthesized on demand, and the Mac voice covers missing keys or no network.
/// Speech never blocks or fails an action.
@Observable @MainActor
final class Speaker {
    enum Engine: String {
        case none = "Not speaking yet"
        case cached = "ElevenLabs (instant, from cache)"
        case live = "ElevenLabs"
        case system = "Mac voice"
    }

    private(set) var lastEngine: Engine = .none
    private(set) var cachedCount = 0
    private(set) var hasKey = false
    private(set) var isPrewarming = false
    /// Silences speech for this run only, without changing the saved preference.
    @ObservationIgnored var muted = false

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?
    @ObservationIgnored private let cacheDirectory: URL

    init(settings: Settings) {
        self.settings = settings
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("Nora/speech", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        reloadKey()
    }

    var knownPhraseCount: Int { SpeechPhrases.known.count }

    func reloadKey() {
        apiKey = KeychainStore.elevenLabsKey()
        hasKey = apiKey != nil
        refreshCacheCount()
    }

    /// Speaks unless the person turned speech off or VoiceOver is already reading Nora's announcements.
    func speak(_ text: String) {
        guard settings.spokenFeedback, !muted, !NSWorkspace.shared.isVoiceOverEnabled else { return }
        generation += 1
        let current = generation
        stop()
        guard settings.useElevenLabs, let apiKey else {
            speakWithMacVoice(text)
            return
        }
        let file = cacheURL(for: text)
        if FileManager.default.fileExists(atPath: file.path) {
            play(file, engine: .cached)
            return
        }
        let client = ElevenLabsClient(apiKey: apiKey)
        let voice = settings.voiceId, speed = settings.speechRate
        Task { [weak self] in
            do {
                let audio = try await client.synthesize(text: text, voiceId: voice, speed: speed, timeout: 2.5)
                try? audio.write(to: file)
                guard let self, current == self.generation else { return }
                self.refreshCacheCount()
                self.play(file, engine: .live)
            } catch {
                guard let self, current == self.generation else { return }
                self.speakWithMacVoice(text)
            }
        }
    }

    func stop() {
        player?.stop()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// Synthesizes every known phrase once, so later feedback plays instantly and works offline.
    func prewarm() {
        refreshCacheCount()
        guard settings.useElevenLabs, let apiKey else { return }
        let missing = SpeechPhrases.known
            .map { (text: $0, file: cacheURL(for: $0)) }
            .filter { !FileManager.default.fileExists(atPath: $0.file.path) }
        guard !missing.isEmpty else { return }
        let client = ElevenLabsClient(apiKey: apiKey)
        let voice = settings.voiceId, speed = settings.speechRate
        prewarmTask?.cancel()
        isPrewarming = true
        prewarmTask = Task { [weak self] in
            for phrase in missing {
                if Task.isCancelled { break }
                if let audio = try? await client.synthesize(text: phrase.text, voiceId: voice, speed: speed, timeout: 15) {
                    try? audio.write(to: phrase.file)
                    self?.refreshCacheCount()
                }
            }
            self?.isPrewarming = false
        }
    }

    func clearCache() {
        prewarmTask?.cancel()
        isPrewarming = false
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        refreshCacheCount()
    }

    private func refreshCacheCount() {
        cachedCount = SpeechPhrases.known.filter { FileManager.default.fileExists(atPath: cacheURL(for: $0).path) }.count
    }

    private func cacheURL(for text: String) -> URL {
        let key = SpeechPhrases.cacheKey(text: text, voiceId: settings.voiceId, speed: settings.speechRate)
        return cacheDirectory.appendingPathComponent("\(key).mp3")
    }

    private func play(_ file: URL, engine: Engine) {
        guard let player = try? AVAudioPlayer(contentsOf: file) else { return }
        self.player = player
        player.play()
        lastEngine = engine
    }

    private func speakWithMacVoice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(settings.speechRate))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
        lastEngine = .system
    }
}
