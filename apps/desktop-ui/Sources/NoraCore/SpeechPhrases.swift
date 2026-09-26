import CryptoKit
import Foundation

public struct VoiceOption: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
}

public enum SpeechPhrases {
    public static let model = "eleven_flash_v2_5"
    public static let sample = "Hi, I’m Nora. Choose a picture, or tell me what you want."

    public static let voices: [VoiceOption] = [
        VoiceOption(id: "JBFqnCBsd6RMkjVDRZzb", name: "George", description: "Warm, steady"),
        VoiceOption(id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", description: "Calm, clear"),
        VoiceOption(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", description: "Soft, friendly"),
    ]

    /// Everything Nora says for known requests. The set is finite, so it can be synthesized once and replayed instantly.
    public static var known: [String] {
        let agent = [
            "Opening Canvas in Microsoft Edge…", "Canvas open request sent to Microsoft Edge.",
            "Opening public dog photos on Google Images…", "Dog photo search sent to Microsoft Edge.",
            "Opening Photos…", "Photos launch request sent.",
            "Opening Microsoft Edge…", "Microsoft Edge launch request sent.",
            "Opening Finder…", "Finder launch request sent.",
            "Sending zoom-in shortcut to the active app…", "Zoom-in shortcut sent to the active app.",
            "Sending zoom-out shortcut to the active app…", "Zoom-out shortcut sent to the active app.",
            "Opening Canvas before looking for Courses…", "Opening the visible Courses control…",
            "Courses is visible in Canvas.",
        ]
        let interface = [
            sample, "Listening.", "Cancelled. Nothing was changed.", "That choice timed out for your safety, so nothing was done.",
            "Top row", "Second row", "Text size", "Scanning paused. Press the switch to start again.",
        ]
        let tiles = TileCatalog.all.map(\.title)
        return agent + interface + tiles
    }

    public static func cacheKey(text: String, voiceId: String, model: String = model, speed: Double) -> String {
        let material = "\(voiceId)|\(model)|\(String(format: "%.2f", speed))|\(text)"
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
