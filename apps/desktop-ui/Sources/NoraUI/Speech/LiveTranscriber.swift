import AVFoundation
import Speech

/// Transcribes the microphone while the person is still talking, with Apple's on-device SpeechAnalyzer.
/// The text is ready as soon as they stop, instead of after a separate pass over a recording.
@available(macOS 26, *)
@MainActor
final class LiveTranscriber {
    /// Converts microphone buffers to the analyzer's format on the audio thread.
    private final class Feed: @unchecked Sendable {
        let continuation: AsyncStream<AnalyzerInput>.Continuation
        let format: AVAudioFormat
        let converter: AVAudioConverter?
        let onLevel: @Sendable (Double) -> Void

        init(continuation: AsyncStream<AnalyzerInput>.Continuation, from input: AVAudioFormat, to format: AVAudioFormat,
             onLevel: @escaping @Sendable (Double) -> Void) {
            self.continuation = continuation
            self.format = format
            converter = input == format ? nil : AVAudioConverter(from: input, to: format)
            self.onLevel = onLevel
        }

        func receive(_ buffer: AVAudioPCMBuffer) {
            onLevel(Self.power(buffer))
            guard let converted = convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }

        private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            guard let converter else { return buffer }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
            var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            return error == nil && output.frameLength > 0 ? output : nil
        }

        /// Loudness in decibels, on the same scale as AVAudioRecorder's meters.
        private static func power(_ buffer: AVAudioPCMBuffer) -> Double {
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -160 }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            return rms > 0 ? Double(20 * log10(rms)) : -160
        }
    }

    private static let locale = Locale(identifier: "en-US")

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var feed: Feed?
    private var results: Task<String, Error>?

    /// Whether this Mac can transcribe English on device.
    static func isSupported() async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    /// Downloads the on-device speech model if it isn't installed yet, so the first request doesn't wait for it.
    static func prepare() async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Starts listening. `onLevel` receives the microphone loudness in decibels, for the meter and pause detection.
    func start(contextualStrings: [String], onLevel: @escaping @Sendable (Double) -> Void,
               onText: @escaping @MainActor (String) -> Void) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Self.locale) else {
            throw CocoaError(.featureUnsupported)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await Self.prepare()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        try await analyzer.setContext(context)

        let input = engine.inputNode.outputFormat(forBus: 0)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: input) else {
            throw CocoaError(.featureUnsupported)
        }
        try await analyzer.prepareToAnalyze(in: format)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let feed = Feed(continuation: continuation, from: input, to: format, onLevel: onLevel)
        results = Task {
            var text = ""
            for try await result in transcriber.results {
                let segment = String(result.text.characters)
                if result.isFinal { text += segment }
                onText(text + (result.isFinal ? "" : segment))
            }
            return text
        }
        try await analyzer.start(inputSequence: stream)
        // The tap runs on an audio thread, never the main actor.
        engine.inputNode.installTap(onBus: 0, bufferSize: 1_024, format: input) { @Sendable buffer, _ in feed.receive(buffer) }
        engine.prepare()
        try engine.start()
        self.analyzer = analyzer
        self.feed = feed
    }

    /// Stops the microphone and returns everything said, once the last words are finalized.
    func finish() async throws -> String {
        stopMicrophone()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        let text = try await results?.value ?? ""
        analyzer = nil
        results = nil
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        stopMicrophone()
        await analyzer?.cancelAndFinishNow()
        results?.cancel()
        analyzer = nil
        results = nil
    }

    private func stopMicrophone() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        feed?.continuation.finish()
        feed = nil
    }
}
