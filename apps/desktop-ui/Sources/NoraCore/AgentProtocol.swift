import Foundation

/// Mirrors `UserInput` in packages/shared/src/types.ts.
public enum UserInput: Sendable, Equatable, Hashable {
    case text(String)
    case voice(String)
    case aac(String)

    public var source: String {
        switch self {
        case .text: "text"
        case .voice: "voice"
        case .aac: "aac"
        }
    }

    /// The words the person typed or said; nil for AAC tiles.
    public var utterance: String? {
        switch self {
        case .text(let text), .voice(let text): text
        case .aac: nil
        }
    }
}

extension UserInput: Codable {
    private enum CodingKeys: String, CodingKey { case source, text, intent }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .source) {
        case "text": self = .text(try container.decode(String.self, forKey: .text))
        case "voice": self = .voice(try container.decode(String.self, forKey: .text))
        case "aac": self = .aac(try container.decode(String.self, forKey: .intent))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .source, in: container, debugDescription: "Unknown input source \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        switch self {
        case .text(let text), .voice(let text): try container.encode(text, forKey: .text)
        case .aac(let intent): try container.encode(intent, forKey: .intent)
        }
    }
}

/// Display-only mirror of `ComputerAction`. Optional fields keep future action types decodable.
public struct ComputerAction: Codable, Sendable, Equatable, Hashable {
    public var type: String
    public var url: String?
    public var browser: String?
    public var app: String?
    public var target: String?
    public var text: String?
    public var key: String?
    public var modifiers: [String]?
    public var direction: String?
    public var amount: Int?

    public init(type: String, url: String? = nil, browser: String? = nil, app: String? = nil,
                target: String? = nil, text: String? = nil, key: String? = nil,
                modifiers: [String]? = nil, direction: String? = nil, amount: Int? = nil) {
        self.type = type
        self.url = url
        self.browser = browser
        self.app = app
        self.target = target
        self.text = text
        self.key = key
        self.modifiers = modifiers
        self.direction = direction
        self.amount = amount
    }
}

public enum RiskLevel: String, Sendable, Equatable, Hashable, Codable {
    case safe, sensitive, destructive

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // An unrecognized level must never be presented as safe.
        self = RiskLevel(rawValue: raw) ?? .sensitive
    }
}

public struct ConfirmationRequest: Sendable, Equatable, Hashable {
    public var id: String
    public var message: String
    public var action: ComputerAction
    public var risk: RiskLevel
    public var expiresAt: Date

    public init(id: String, message: String, action: ComputerAction, risk: RiskLevel, expiresAt: Date) {
        self.id = id
        self.message = message
        self.action = action
        self.risk = risk
        self.expiresAt = expiresAt
    }
}

public enum ResolutionReason: String, Sendable, Equatable {
    case approved, cancelled, expired, invalidated
}

public enum AgentEvent: Sendable, Equatable {
    case listening
    case thinking(String?)
    case acting(String)
    case confirmationRequired(ConfirmationRequest)
    case confirmationResolved(id: String, reason: ResolutionReason)
    case done(String?)
    case error(String)
    case unrecognized(String)
}

extension AgentEvent: Decodable {
    private enum CodingKeys: String, CodingKey { case type, message, confirmationId, action, risk, expiresAt, reason }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "listening":
            self = .listening
        case "thinking":
            self = .thinking(try container.decodeIfPresent(String.self, forKey: .message))
        case "acting":
            self = .acting(try container.decode(String.self, forKey: .message))
        case "confirmation_required":
            let expiresAt = try container.decode(Double.self, forKey: .expiresAt)
            self = .confirmationRequired(ConfirmationRequest(
                id: try container.decode(String.self, forKey: .confirmationId),
                message: try container.decode(String.self, forKey: .message),
                action: try container.decode(ComputerAction.self, forKey: .action),
                risk: try container.decode(RiskLevel.self, forKey: .risk),
                expiresAt: Date(timeIntervalSince1970: expiresAt / 1000)))
        case "confirmation_resolved":
            let reason = try container.decode(String.self, forKey: .reason)
            self = .confirmationResolved(id: try container.decode(String.self, forKey: .confirmationId),
                                         reason: ResolutionReason(rawValue: reason) ?? .invalidated)
        case "done":
            self = .done(try container.decodeIfPresent(String.self, forKey: .message))
        case "error":
            self = .error(try container.decode(String.self, forKey: .message))
        default:
            self = .unrecognized(type)
        }
    }
}

public enum AgentResult: Sendable, Equatable {
    case success(String?)
    case failure(String)
    case needsConfirmation(id: String, message: String)
}

extension AgentResult: Decodable {
    private enum CodingKeys: String, CodingKey { case success, message, error, requiresConfirmation, confirmationId }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .success) {
            self = .success(try container.decodeIfPresent(String.self, forKey: .message))
        } else if try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) == true {
            self = .needsConfirmation(id: try container.decode(String.self, forKey: .confirmationId),
                                      message: try container.decode(String.self, forKey: .message))
        } else {
            self = .failure(try container.decodeIfPresent(String.self, forKey: .error) ?? "The request failed.")
        }
    }
}

/// Mirrors `AgentHistoryEntry`: a redacted, display-only record of one controller attempt.
public struct HistoryEntry: Decodable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var action: ComputerAction
    public var success: Bool
    public var timestamp: Double
    public var completedAt: Double

    public var startedAt: Date { Date(timeIntervalSince1970: timestamp / 1000) }
    public var duration: TimeInterval { max(0, completedAt - timestamp) / 1000 }
}

public enum AgentMessage: Sendable, Equatable {
    case event(requestId: String, AgentEvent)
    case result(requestId: String, AgentResult)
    case history(requestId: String, [HistoryEntry])
    case protocolError(requestId: String?, String)

    public var requestId: String? {
        switch self {
        case .event(let id, _), .result(let id, _), .history(let id, _): id
        case .protocolError(let id, _): id
        }
    }
}

extension AgentMessage: Decodable {
    private enum CodingKeys: String, CodingKey { case type, requestId, event, result, entries, error }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "event":
            self = .event(requestId: try container.decode(String.self, forKey: .requestId),
                          try container.decode(AgentEvent.self, forKey: .event))
        case "result":
            self = .result(requestId: try container.decode(String.self, forKey: .requestId),
                           try container.decode(AgentResult.self, forKey: .result))
        case "history":
            self = .history(requestId: try container.decode(String.self, forKey: .requestId),
                            try container.decode([HistoryEntry].self, forKey: .entries))
        case "protocol_error":
            self = .protocolError(requestId: try container.decodeIfPresent(String.self, forKey: .requestId),
                                  try container.decode(String.self, forKey: .error))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type \(other)")
        }
    }
}

/// Requests accepted by `serveAgent` in packages/agent/src/transport.ts.
public enum AgentRequest: Sendable, Equatable {
    case submit(requestId: String, input: UserInput)
    case confirm(requestId: String, confirmationId: String, approved: Bool)
    case getHistory(requestId: String)
    case clearHistory(requestId: String)

    public var requestId: String {
        switch self {
        case .submit(let id, _), .confirm(let id, _, _), .getHistory(let id), .clearHistory(let id): id
        }
    }
}

extension AgentRequest: Encodable {
    private enum CodingKeys: String, CodingKey { case type, requestId, input, confirmationId, approved }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        switch self {
        case .submit(_, let input):
            try container.encode("submit", forKey: .type)
            try container.encode(input, forKey: .input)
        case .confirm(_, let confirmationId, let approved):
            try container.encode("confirm", forKey: .type)
            try container.encode(confirmationId, forKey: .confirmationId)
            try container.encode(approved, forKey: .approved)
        case .getHistory:
            try container.encode("get_history", forKey: .type)
        case .clearHistory:
            try container.encode("clear_history", forKey: .type)
        }
    }
}

public enum AgentCodec {
    public static func encodeLine(_ request: AgentRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(request)
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) throws -> AgentMessage {
        try JSONDecoder().decode(AgentMessage.self, from: line)
    }
}
