import Foundation
import NoraCore

struct ElevenLabsError: LocalizedError, Sendable {
    var statusCode: Int?
    var message: String
    var errorDescription: String? { message }
}

/// Minimal ElevenLabs REST client: text to speech (Flash v2.5) and speech to text (Scribe v2).
struct ElevenLabsClient: Sendable {
    let apiKey: String
    private static let base = URL(string: "https://api.elevenlabs.io")!

    func synthesize(text: String, voiceId: String, speed: Double, timeout: TimeInterval) async throws -> Data {
        var components = URLComponents(url: Self.base.appendingPathComponent("v1/text-to-speech/\(voiceId)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "text": text,
            "model_id": SpeechPhrases.model,
            "voice_settings": ["stability": 0.55, "similarity_boost": 0.75, "speed": speed],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return data
    }

    /// Transcribes a short recording, biased toward the person's own vocabulary.
    func transcribe(audio: URL, keyterms: [String], timeout: TimeInterval = 20) async throws -> String {
        do {
            return try await transcribeOnce(audio: audio, keyterms: keyterms, timeout: timeout)
        } catch let error as ElevenLabsError where [400, 422].contains(error.statusCode ?? 0) && !keyterms.isEmpty {
            return try await transcribeOnce(audio: audio, keyterms: [], timeout: timeout)
        }
    }

    func voiceCount() async throws -> Int {
        var request = URLRequest(url: Self.base.appendingPathComponent("v1/voices"), timeoutInterval: 10)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        struct Voices: Decodable { let voices: [Voice]; struct Voice: Decodable { let voice_id: String } }
        return try JSONDecoder().decode(Voices.self, from: data).voices.count
    }

    private func transcribeOnce(audio: URL, keyterms: [String], timeout: TimeInterval) async throws -> String {
        let boundary = "nora-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model_id", "scribe_v2")
        field("language_code", "en")
        field("tag_audio_events", "false")
        for term in keyterms { field("keyterms", term) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(try Data(contentsOf: audio))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: Self.base.appendingPathComponent("v1/speech-to-text"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try Self.check(response, data)
        struct Transcript: Decodable { let text: String }
        return try JSONDecoder().decode(Transcript.self, from: data).text
    }

    /// Scribe rejects keyterms over five words, 50 characters, or containing brackets and braces.
    static func sanitizedKeyterms(_ terms: [String]) -> [String] {
        let forbidden = CharacterSet(charactersIn: "<>{}[]\\")
        var seen = Set<String>()
        var accepted: [String] = []
        for raw in terms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = term.split(separator: " ").count
            guard !term.isEmpty, term.count < 50, wordCount <= 5, term.rangeOfCharacter(from: forbidden) == nil else { continue }
            if seen.insert(term.lowercased()).inserted { accepted.append(term) }
        }
        return accepted
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError(statusCode: nil, message: "ElevenLabs did not respond.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(decoding: data.prefix(240), as: UTF8.self)
            let message = http.statusCode == 401 ? "The ElevenLabs key was not accepted." : "ElevenLabs returned \(http.statusCode). \(detail)"
            throw ElevenLabsError(statusCode: http.statusCode, message: message)
        }
    }
}
