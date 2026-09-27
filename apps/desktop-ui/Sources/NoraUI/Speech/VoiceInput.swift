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

    @ObservationIgnored var onTranscript: (String) -> Void = { _ in }
    @ObservationIgnored var keyterms: () -> [String] = { Vocabulary.recognitionKeyterms }
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptTask: Task<Void, Never>?
    @ObservationIgnored private var heardSpeech = false
    @ObservationIgnored private var silenceStartedAt: Date?
    @ObservationIgnored private var startedAt = Date()

    var isListening: Bool { if case .listening = state { true } else { false } }
    var isBusy: Bool {
        switch state {
        case .listening, .transcribing: true
        default: false
        }
    }

    func toggle() {
        switch state {
        case .listening: finishRecording()
        case .transcribing: break
        case .idle, .failed: Task { await begin() }
        }
    }

    func cancel() {
        meterTask?.cancel()
        transcriptTask?.cancel()
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
            state = .failed(.needsAppBundle)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                state = .failed(.microphoneDenied)
                return
            }
        default:
            state = .failed(.microphoneDenied)
            return
        }
        startRecording()
    }

    private func startRecording() {
        transcriptTask?.cancel()
        recentTranscript = ""
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nora-speech-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: file, settings: settings) else {
            state = .failed(.service("The microphone couldn’t start."))
            return
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            state = .failed(.service("The microphone couldn’t start."))
            return
        }
        self.recorder = recorder
        heardSpeech = false
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
        guard let recorder, isListening else { return }
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))
        state = .listening(level: max(0, min(1, (power + 50) / 50)))
        let now = Date()
        if power > -38 {
            heardSpeech = true
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
        Task { [weak self] in await self?.transcribe(file) }
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
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                state = .failed(.nothingHeard)
                return
            }
            recentTranscript = trimmed
            state = .idle
            onTranscript(trimmed)
            transcriptTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, self?.recentTranscript == trimmed else { return }
                self?.recentTranscript = ""
            }
        } catch {
            state = .failed(.service(error.localizedDescription))
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
