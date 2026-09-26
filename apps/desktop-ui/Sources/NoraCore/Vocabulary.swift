import Foundation

/// One AAC tile. `intent` must be an AAC intent accepted by packages/agent/src/router.ts.
public struct TileSpec: Sendable, Equatable, Hashable, Identifiable {
    public var intent: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var color: UInt32
    public var shortcut: String

    public var id: String { intent }

    public init(intent: String, title: String, detail: String, symbol: String, color: UInt32, shortcut: String) {
        self.intent = intent
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.color = color
        self.shortcut = shortcut
    }
}

public enum TileCatalog {
    /// Positions are part of the interface: AAC users learn a location, so tiles never reorder.
    public static let home: [TileSpec] = [
        TileSpec(intent: "OPEN_SCHOOL", title: "School", detail: "Open Canvas", symbol: "graduationcap.fill", color: 0x1E4FA3, shortcut: "1"),
        TileSpec(intent: "OPEN_COURSES", title: "Courses", detail: "My Canvas courses", symbol: "books.vertical.fill", color: 0x5B2A86, shortcut: "2"),
        TileSpec(intent: "OPEN_INTERNET", title: "Internet", detail: "Open Edge", symbol: "globe", color: 0x095566, shortcut: "3"),
        TileSpec(intent: "OPEN_PHOTOS", title: "Photos", detail: "Open Photos", symbol: "photo.on.rectangle.angled", color: 0x9C1D5A, shortcut: "4"),
        TileSpec(intent: "OPEN_DOG_PHOTOS", title: "Dogs", detail: "Dog pictures", symbol: "pawprint.fill", color: 0x7A4100, shortcut: "5"),
        TileSpec(intent: "OPEN_FINDER", title: "Files", detail: "Open Finder", symbol: "folder.fill", color: 0x37474F, shortcut: "6"),
    ]

    public static let textSize: [TileSpec] = [
        TileSpec(intent: "ZOOM_OUT", title: "Smaller", detail: "Make text smaller", symbol: "minus.magnifyingglass", color: 0x262626, shortcut: "-"),
        TileSpec(intent: "ZOOM_IN", title: "Bigger", detail: "Make text bigger", symbol: "plus.magnifyingglass", color: 0x262626, shortcut: "="),
    ]

    public static let all: [TileSpec] = home + textSize

    /// Rows used by switch scanning, in visual order.
    public static let scanRows: [[TileSpec]] = [Array(home[0..<3]), Array(home[3..<6]), textSize]

    public static func tile(for intent: String) -> TileSpec? {
        all.first { $0.intent == intent }
    }
}

public struct Phrase: Sendable, Equatable {
    public var intent: String
    public var label: String
    public var keywords: [String]
}

public struct Suggestion: Sendable, Equatable, Hashable, Identifiable {
    public var intent: String
    public var label: String
    public var id: String { intent }

    public init(intent: String, label: String) {
        self.intent = intent
        self.label = label
    }
}

public enum Vocabulary {
    public static let phrases: [Phrase] = [
        Phrase(intent: "OPEN_SCHOOL", label: "Open Canvas",
               keywords: ["canvas", "school", "schoolwork", "homework", "assignment", "assignments", "class", "temple", "study"]),
        Phrase(intent: "OPEN_COURSES", label: "Go to my Canvas courses",
               keywords: ["courses", "course", "classes", "syllabus", "grades"]),
        Phrase(intent: "OPEN_DOG_PHOTOS", label: "Show me dog photos",
               keywords: ["dog", "dogs", "puppy", "puppies", "pet", "pets"]),
        Phrase(intent: "OPEN_PHOTOS", label: "Open Photos",
               keywords: ["photos", "photo", "pictures", "picture", "pics", "images", "gallery", "camera"]),
        Phrase(intent: "OPEN_INTERNET", label: "Open the internet",
               keywords: ["internet", "web", "browser", "edge", "google", "online", "website", "search"]),
        Phrase(intent: "OPEN_FINDER", label: "Open my files",
               keywords: ["files", "file", "finder", "documents", "document", "folder", "folders", "downloads", "desktop"]),
        Phrase(intent: "ZOOM_IN", label: "Make text bigger",
               keywords: ["bigger", "larger", "big", "large", "enlarge", "increase", "zoom", "magnify", "text", "see", "read"]),
        Phrase(intent: "ZOOM_OUT", label: "Make text smaller",
               keywords: ["smaller", "small", "shrink", "decrease", "reduce", "zoom", "text"]),
    ]

    /// Mirrors the agent's own hint for unknown requests.
    public static let fallbackIntents = ["OPEN_SCHOOL", "OPEN_DOG_PHOTOS", "ZOOM_IN"]

    /// Typed examples shown under the text field so nobody has to recall exact wording.
    public static let examples = ["Open Canvas", "Show me dog photos", "Open Canvas and go to Courses"]

    public static func phrase(for intent: String) -> Phrase? {
        phrases.first { $0.intent == intent }
    }

    /// Words worth biasing speech recognition toward.
    public static var recognitionKeyterms: [String] {
        var terms = ["Canvas", "Courses", "Edge", "Finder", "Photos", "Temple", "Nora"]
        terms += phrases.map(\.label)
        return terms
    }
}

/// Turns a failed request into a short list of recognizable choices (communication repair).
public enum Repair {
    public static func suggestions(for text: String, limit: Int = 3) -> [Suggestion] {
        let tokens = tokenize(text)
        var scored: [(index: Int, phrase: Phrase, score: Double)] = []
        for (index, phrase) in Vocabulary.phrases.enumerated() {
            let value = score(tokens, phrase.keywords)
            if value > 0 { scored.append((index, phrase, value)) }
        }
        scored.sort { lhs, rhs in lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index }
        let chosen: [Phrase] = scored.isEmpty
            ? Vocabulary.fallbackIntents.compactMap(Vocabulary.phrase(for:))
            : scored.map(\.phrase)
        return chosen.prefix(limit).map { Suggestion(intent: $0.intent, label: $0.label) }
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func score(_ tokens: [String], _ keywords: [String]) -> Double {
        tokens.reduce(0) { total, token in
            total + (keywords.map { similarity(token, $0) }.max() ?? 0)
        }
    }

    static func similarity(_ token: String, _ keyword: String) -> Double {
        if token == keyword { return 3 }
        if token.count >= 4, keyword.count >= 4, token.hasPrefix(keyword) || keyword.hasPrefix(token) { return 2 }
        let distance = editDistance(token, keyword)
        if (keyword.count >= 5 && distance == 1) || (keyword.count >= 8 && distance == 2) { return 1.5 }
        return 0
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
