import Foundation

/// A personal phrase that stands for a tile, e.g. “my school thing” → School.
public struct Alias: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var phrase: String
    public var intent: String

    public init(id: UUID = UUID(), phrase: String, intent: String) {
        self.id = id
        self.phrase = phrase
        self.intent = intent
    }
}

public enum AliasResolver {
    /// Same normalization as the agent router: case, surrounding space, trailing punctuation, and “please”.
    public static func normalize(_ text: String) -> String {
        var request = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        request = request.replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)
        request = request.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if request.hasPrefix("please ") { request.removeFirst("please ".count) }
        if request.hasSuffix(" please") { request.removeLast(" please".count) }
        return request
    }

    public static func intent(for text: String, aliases: [Alias]) -> String? {
        let request = normalize(text)
        guard !request.isEmpty else { return nil }
        return aliases.first { normalize($0.phrase) == request && TileCatalog.tile(for: $0.intent) != nil }?.intent
    }
}
