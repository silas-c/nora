import AppKit
import AVFoundation
import NoraCore
import Observation
import Speech

/// Push-to-talk for issue #8. One tap starts listening and Nora stops by itself after a pause,
/// so nobody has to hold a button down. Start and stop use sounds rather than speech, which
/// would otherwise be recorded.
@Observable @MainActor
final class VoiceInput {
    enum Failure: Equatable {
        case microphoneDenied
        case needsAppBundle
        case nothingHeard
        case service(String)
    }

    enum State: Equatable {
        case idle
        case listening(level: Double)
        case transcribing
        case failed(Failure)
    }

    private(set) var state: State = .idle
    private(set) var lastEngine = ""
    private(set) var recentTranscript = ""
    private(set) var liveTranscript = ""
    private(set) var lastSpeechToTranscriptMs: Int?
    private(set) var isStarting = false

    @ObservationIgnored var onTranscript: (String) -> Void = { _ in }
    @ObservationIgnored var keyterms: () -> [String] = { Vocabulary.recognitionKeyterms }
    @ObservationIgnored private var recorder: AVAudioRecorder?
    /// A `LiveTranscriber` while SpeechAnalyzer is listening (macOS 26 and later).
    @ObservationIgnored private var live: AnyObject?
    @ObservationIgnored private var livePower = -160.0
    @ObservationIgnored private var liveFinish: Task<Void, Never>?
    @ObservationIgnored private var beginTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptTask: Task<Void, Never>?
    @ObservationIgnored private var heardSpeech = false
    @ObservationIgnored private var lastSpeechAt: Date?
    @ObservationIgnored private var silenceStartedAt: Date?
    @ObservationIgnored private var startedAt = Date()

    var isListening: Bool { if case .listening = state { true } else { isStarting } }
    var isBusy: Bool {
        if isStarting { return true }
        return switch state {
        case .listening, .transcribing: true
        default: false
        }
    }

    func toggle() {
        if isStarting { cancel(); return }
        switch state {
        case .listening: finishRecording()
        case .transcribing: break
        case .idle, .failed:
            isStarting = true
            beginTask = Task { await begin() }
        }
    }

    /// Downloads Apple's on-device speech model in the background, so the first request doesn't wait for it.
    func prewarm() {
        guard KeychainStore.elevenLabsKey() == nil, #available(macOS 26, *) else { return }
        Task { try? await LiveTranscriber.prepare() }
    }

    func cancel() {
        beginTask?.cancel()
        transcriptionTask?.cancel()
        isStarting = false
        meterTask?.cancel()
        transcriptTask?.cancel()
        liveFinish?.cancel()
        if #available(macOS 26, *), let live = live as? LiveTranscriber { Task { await live.cancel() } }
        live = nil
        liveTranscript = ""
        if let recorder {
            recorder.stop()
            try? FileManager.default.removeItem(at: recorder.url)
        }
        recorder = nil
        if isBusy { state = .idle }
    }

    func clearFailure() {
        if case .failed = state { state = .idle }
    }

    private func begin() async {
        // Without a usage description macOS terminates the process when the microphone is requested.
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            isStarting = false
            state = .failed(.needsAppBundle)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                guard !Task.isCancelled else { return }
                isStarting = false
                state = .failed(.microphoneDenied)
                return
            }
        default:
            isStarting = false
            state = .failed(.microphoneDenied)
            return
        }
        guard !Task.isCancelled else { return }
        if await startLive() { return }
        guard !Task.isCancelled else { return }
        startRecording()
    }

    /// Apple's SpeechAnalyzer transcribes while the person talks. With an ElevenLabs key, on older Macs, or if the
    /// analyzer can't start, Nora records first and transcribes afterwards.
    private func startLive() async -> Bool {
        guard KeychainStore.elevenLabsKey() == nil, #available(macOS 26, *), await LiveTranscriber.isSupported() else { return false }
        let transcriber = LiveTranscriber()
        do {
            try await transcriber.start(contextualStrings: keyterms()) { [weak self] power in
                Task { @MainActor in self?.livePower = power }
            } onText: { [weak self] text in
                self?.liveTranscript = text
            }
        } catch {
            await transcriber.cancel()
            return false
        }
        if Task.isCancelled {
            await transcriber.cancel()
            return false
        }
        transcriptTask?.cancel()
        recentTranscript = ""
        liveTranscript = ""
        live = transcriber
        livePower = -160
        beginListening()
        return true
    }

    private func startRecording() {
        transcriptTask?.cancel()
        recentTranscript = ""
        liveTranscript = ""
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nora-speech-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: file, settings: settings) else {
            isStarting = false
            state = .failed(.service("The microphone couldn’t start."))
            return
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            isStarting = false
            state = .failed(.service("The microphone couldn’t start."))
            return
        }
        self.recorder = recorder
        beginListening()
    }

    private func beginListening() {
        isStarting = false
        heardSpeech = false
        lastSpeechAt = nil
        lastSpeechToTranscriptMs = nil
        silenceStartedAt = nil
        startedAt = Date()
        state = .listening(level: 0)
        NSSound(named: "Tink")?.play()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                self?.updateMeter()
            }
        }
    }

    private func updateMeter() {
        guard isListening else { return }
        let power: Double
        if let recorder {
            recorder.updateMeters()
            power = Double(recorder.averagePower(forChannel: 0))
        } else if live != nil {
            power = livePower
        } else {
            return
        }
        state = .listening(level: max(0, min(1, (power + 50) / 50)))
        let now = Date()
        if power > -38 {
            heardSpeech = true
            lastSpeechAt = now
            silenceStartedAt = nil
        } else if silenceStartedAt == nil {
            silenceStartedAt = now
        }
        let silence = silenceStartedAt.map { now.timeIntervalSince($0) } ?? 0
        let elapsed = now.timeIntervalSince(startedAt)
        if (heardSpeech && silence > 1.4) || (!heardSpeech && elapsed > 7) || elapsed > 15 {
            finishRecording()
        }
    }

    private func finishRecording() {
        if #available(macOS 26, *), let live = live as? LiveTranscriber {
            self.live = nil
            liveTranscript = ""
            meterTask?.cancel()
            NSSound(named: "Pop")?.play()
            guard heardSpeech else {
                Task { await live.cancel() }
                state = .failed(.nothingHeard)
                return
            }
            state = .transcribing
            lastEngine = "Apple SpeechAnalyzer"
            liveFinish = Task { [weak self] in
                do {
                    let text = try await live.finish()
                    guard !Task.isCancelled else { return }
                    self?.deliver(text)
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.state = .failed(.service(error.localizedDescription))
                }
            }
            return
        }
        guard let recorder else { return }
        let file = recorder.url
        recorder.stop()
        self.recorder = nil
        meterTask?.cancel()
        NSSound(named: "Pop")?.play()
        guard heardSpeech else {
            try? FileManager.default.removeItem(at: file)
            state = .failed(.nothingHeard)
            return
        }
        state = .transcribing
        transcriptionTask = Task { [weak self] in await self?.transcribe(file) }
    }

    private func transcribe(_ file: URL) async {
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            let text: String
            if let key = KeychainStore.elevenLabsKey() {
                lastEngine = "ElevenLabs Scribe v2"
                text = try await ElevenLabsClient(apiKey: key)
                    .transcribe(audio: file, keyterms: ElevenLabsClient.sanitizedKeyterms(keyterms()))
            } else {
                lastEngine = "Apple speech recognition"
                text = try await AppleSpeech.transcribe(file, contextualStrings: keyterms())
            }
            guard !Task.isCancelled else { return }
            deliver(text)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(.service(error.localizedDescription))
        }
    }

    private func deliver(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed(.nothingHeard)
            return
        }
        recentTranscript = trimmed
        lastSpeechToTranscriptMs = lastSpeechAt.map { Int(Date().timeIntervalSince($0) * 1_000) }
        state = .idle
        onTranscript(trimmed)
        transcriptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, self?.recentTranscript == trimmed else { return }
            self?.recentTranscript = ""
        }
    }
}

/// On-device fallback when no ElevenLabs key is configured.
enum AppleSpeech {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Speech recognition is turned off. Add an ElevenLabs key in Settings, or allow Speech Recognition in System Settings." }
    }

    static func transcribe(_ file: URL, contextualStrings: [String]) async throws -> String {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else { throw Unavailable() }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            throw Unavailable()
        }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.contextualStrings = contextualStrings
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if once.claim() { continuation.resume(throwing: error) }
                } else if let result, result.isFinal {
                    if once.claim() { continuation.resume(returning: result.bestTranscription.formattedString) }
                }
            }
        }
    }
}
