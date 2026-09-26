import Foundation

public enum WorkStage: Sendable, Equatable {
    case thinking
    case acting
}

public enum Outcome: String, Sendable, Equatable {
    case succeeded
    case failed
    case notUnderstood = "not understood"
    case cancelled
    case expired
}

public struct CompletedRequest: Sendable, Equatable {
    public var input: UserInput
    public var startedAt: Date
    public var finishedAt: Date
    public var outcome: Outcome
    public var message: String
}

public enum Phase: Sendable, Equatable {
    case connecting
    case idle
    case listening(String?)
    case working(WorkStage, String)
    case confirming(ConfirmationRequest, decisionSent: Bool)
    case done(String, cancelled: Bool)
    case failed(FailureInfo)
    case disconnected(FailureInfo)
}

public enum Effect: Sendable, Equatable {
    case send(AgentRequest)
    case announce(String, urgent: Bool)
    case completed(CompletedRequest)
}

/// The interface's view of one agent session. Pure state: feed it protocol messages, perform the effects it returns.
public struct InteractionModel: Sendable {
    public private(set) var phase: Phase = .connecting
    public private(set) var activeRequestId: String?
    public private(set) var pendingConfirmation: ConfirmationRequest?
    public private(set) var lastInput: UserInput?

    private var decisionApproved: Bool?
    private var startedAt: Date?
    private var finalAnnounced = false
    private var counter = 0
    private let tag: String

    public init(tag: String = String(UUID().uuidString.prefix(8)).lowercased()) {
        self.tag = tag
    }

    /// While busy every input control is disabled, so tremor or switch bounce cannot double-submit.
    public var isBusy: Bool {
        if activeRequestId != nil || pendingConfirmation != nil { return true }
        switch phase {
        case .connecting, .disconnected: return true
        default: return false
        }
    }

    public var acceptsInput: Bool { !isBusy }

    public mutating func connected() {
        if case .connecting = phase { phase = .idle }
    }

    public mutating func reconnecting() {
        clearRequestState()
        phase = .connecting
    }

    public mutating func disconnected(_ failure: FailureInfo) -> [Effect] {
        clearRequestState()
        phase = .disconnected(failure)
        return [.announce(failure.message, urgent: true)]
    }

    public mutating func submit(_ input: UserInput, at now: Date = Date()) -> [Effect] {
        guard acceptsInput else { return [] }
        let id = nextRequestId(input.source)
        activeRequestId = id
        lastInput = input
        startedAt = now
        decisionApproved = nil
        finalAnnounced = false
        phase = .working(.thinking, "Working on it…")
        return [.send(.submit(requestId: id, input: input))]
    }

    public mutating func askAgain(at now: Date = Date()) -> [Effect] {
        guard let lastInput else { return [] }
        return submit(lastInput, at: now)
    }

    /// Each prompt accepts exactly one decision; later presses are ignored.
    public mutating func decide(approved: Bool) -> [Effect] {
        guard activeRequestId == nil, let confirmation = pendingConfirmation,
              case .confirming(let shown, false) = phase, shown.id == confirmation.id else { return [] }
        let id = nextRequestId(approved ? "approve" : "cancel")
        activeRequestId = id
        decisionApproved = approved
        finalAnnounced = false
        phase = .confirming(confirmation, decisionSent: true)
        return [.send(.confirm(requestId: id, confirmationId: confirmation.id, approved: approved))]
    }

    public mutating func dismiss() {
        guard !isBusy else { return }
        phase = .idle
    }

    public mutating func receive(_ message: AgentMessage, at now: Date = Date()) -> [Effect] {
        switch message {
        case .event(_, .confirmationResolved(let id, let reason)):
            // Resolutions arrive on the original submission's request ID, including asynchronous expiry.
            return resolve(id, reason: reason, at: now)
        case .event(let requestId, let event):
            guard requestId == activeRequestId else { return [] }
            return apply(event)
        case .result(let requestId, let result):
            guard requestId == activeRequestId else { return [] }
            activeRequestId = nil
            return finish(result, at: now)
        case .protocolError(let requestId, let error):
            guard let requestId, requestId == activeRequestId else { return [] }
            activeRequestId = nil
            pendingConfirmation = nil
            let failure = FailureInfo(kind: .connection, message: "Nora and its agent couldn’t understand each other.",
                                      detail: error, recovery: .restartAgent)
            phase = .failed(failure)
            return [.announce(failure.message, urgent: true)] + completion(.failed, message: error, at: now)
        case .history:
            return []
        }
    }

    private mutating func apply(_ event: AgentEvent) -> [Effect] {
        switch event {
        case .listening:
            phase = .listening(nil)
            return []
        case .thinking(let message):
            phase = .working(.thinking, message ?? "Working on it…")
            return []
        case .acting(let message):
            phase = .working(.acting, message)
            return [.announce(message, urgent: false)]
        case .confirmationRequired(let confirmation):
            pendingConfirmation = confirmation
            phase = .confirming(confirmation, decisionSent: false)
            return [.announce("Please confirm. \(ActionDescriber.headline(confirmation)).", urgent: true)]
        case .done(let message):
            let cancelled = decisionApproved == false
            phase = .done(cancelled ? "Nothing was changed." : (message ?? "Done."), cancelled: cancelled)
            finalAnnounced = true
            return [.announce(cancelled ? "Cancelled. Nothing was changed." : (message ?? "Done."), urgent: false)]
        case .error(let message):
            let failure = PlainLanguage.failure(for: message, input: lastInput)
            phase = .failed(failure)
            finalAnnounced = true
            return [.announce(failure.message, urgent: true)]
        case .confirmationResolved, .unrecognized:
            return []
        }
    }

    private mutating func finish(_ result: AgentResult, at now: Date) -> [Effect] {
        let wasDecision = decisionApproved != nil
        if wasDecision { pendingConfirmation = nil }
        switch result {
        case .success(let message):
            let cancelled = decisionApproved == false
            var effects: [Effect] = []
            if case .done = phase {} else {
                phase = .done(cancelled ? "Nothing was changed." : (message ?? "Done."), cancelled: cancelled)
                if !finalAnnounced {
                    effects.append(.announce(cancelled ? "Cancelled. Nothing was changed." : (message ?? "Done."), urgent: false))
                }
            }
            return effects + completion(cancelled ? .cancelled : .succeeded, message: message ?? "", at: now)
        case .failure(let error):
            var effects: [Effect] = []
            var failure = PlainLanguage.failure(for: error, input: lastInput)
            if case .failed(let shown) = phase {
                failure = shown
            } else {
                phase = .failed(failure)
                if !finalAnnounced { effects.append(.announce(failure.message, urgent: true)) }
            }
            return effects + completion(failure.kind == .notUnderstood ? .notUnderstood : .failed, message: error, at: now)
        case .needsConfirmation(let id, let message):
            if pendingConfirmation?.id != id {
                let confirmation = ConfirmationRequest(id: id, message: message, action: ComputerAction(type: "unknown"),
                                                       risk: .sensitive, expiresAt: now.addingTimeInterval(60))
                pendingConfirmation = confirmation
                phase = .confirming(confirmation, decisionSent: false)
                return [.announce("Please confirm. \(ActionDescriber.headline(confirmation)).", urgent: true)]
            }
            return []
        }
    }

    private mutating func resolve(_ id: String, reason: ResolutionReason, at now: Date) -> [Effect] {
        guard pendingConfirmation?.id == id else { return [] }
        pendingConfirmation = nil
        switch reason {
        case .approved:
            phase = .working(.acting, "Confirmed. Working on it…")
            return []
        case .cancelled:
            if activeRequestId == nil { phase = .idle }
            return []
        case .expired, .invalidated:
            // A decision already in flight reports its own result; only explain here when nothing else will.
            guard activeRequestId == nil else { return [] }
            let failure = reason == .expired
                ? FailureInfo(kind: .expired, message: "That choice timed out for your safety, so nothing was done.",
                              detail: "Confirmation expired.", recovery: .askAgain)
                : FailureInfo(kind: .actionFailed, message: "Something changed, so Nora stopped. Nothing was done.",
                              detail: "Confirmation invalidated.", recovery: .askAgain)
            phase = .failed(failure)
            return [.announce(failure.message, urgent: true)]
                + completion(reason == .expired ? .expired : .failed, message: failure.detail, at: now)
        }
    }

    private mutating func completion(_ outcome: Outcome, message: String, at now: Date) -> [Effect] {
        defer {
            startedAt = nil
            decisionApproved = nil
        }
        guard let input = lastInput, let startedAt else { return [] }
        return [.completed(CompletedRequest(input: input, startedAt: startedAt, finishedAt: now, outcome: outcome, message: message))]
    }

    private mutating func clearRequestState() {
        activeRequestId = nil
        pendingConfirmation = nil
        decisionApproved = nil
        startedAt = nil
    }

    private mutating func nextRequestId(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)-\(tag)"
    }
}
