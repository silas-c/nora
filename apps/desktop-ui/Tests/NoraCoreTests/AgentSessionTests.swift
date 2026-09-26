import Foundation
import Testing
@testable import NoraCore

private let agentAvailable = (try? AgentLocator.configuration(mode: .mock)) != nil

/// Buffers protocol messages on the main actor and hands them out one reply at a time.
@MainActor
final class Inbox {
    private var messages: [AgentMessage] = []
    private var cursor = 0
    private(set) var terminated = false

    init(_ session: AgentSession) {
        session.onEvent = { [weak self] event in
            switch event {
            case .received(let message, _): self?.messages.append(message)
            case .terminated: self?.terminated = true
            default: break
            }
        }
    }

    /// Everything received since the previous call, through the result or history for `requestId`.
    func take(until requestId: String) async -> [AgentMessage] {
        while true {
            if let end = messages[cursor...].firstIndex(where: { Self.isReply($0, to: requestId) }) {
                defer { cursor = end + 1 }
                return Array(messages[cursor...end])
            }
            if terminated {
                defer { cursor = messages.count }
                return Array(messages[cursor...])
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func isReply(_ message: AgentMessage, to requestId: String) -> Bool {
        switch message {
        case .result(let id, _), .history(let id, _): id == requestId
        case .protocolError(let id, _): id == requestId
        case .event: false
        }
    }
}

/// End-to-end checks against the real agent and transport, using the mock-only server.
@MainActor
@Suite("Agent session (real agent, mock controller)", .enabled(if: agentAvailable), .serialized)
struct AgentSessionTests {
    private func start() throws -> (AgentSession, Inbox) {
        let session = AgentSession(configuration: try AgentLocator.configuration(mode: .mock))
        let inbox = Inbox(session)
        try session.start()
        return (session, inbox)
    }

    @Test(.timeLimit(.minutes(1)))
    func schoolTileAndTypedRequestReachTheSameSkill() async throws {
        let (session, inbox) = try start()
        defer { session.stop() }
        var model = InteractionModel(tag: "it")
        model.connected()

        for input in [UserInput.aac("OPEN_SCHOOL"), .text("Open Canvas")] {
            guard case .send(let request) = try #require(model.submit(input).first) else {
                Issue.record("Expected a request")
                return
            }
            try session.send(request)
            var sawActing = false
            for message in await inbox.take(until: request.requestId) {
                _ = model.receive(message)
                if case .event(_, .acting) = message { sawActing = true }
            }
            #expect(sawActing)
            #expect(model.phase == .done("Canvas open request sent to Microsoft Edge.", cancelled: false))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func everyTileIsUnderstoodByTheLiveRouter() async throws {
        let (session, inbox) = try start()
        defer { session.stop() }
        for (index, tile) in TileCatalog.all.enumerated() {
            let id = "tile-\(index)"
            try session.send(.submit(requestId: id, input: .aac(tile.intent)))
            guard case .result(_, let result) = try #require(await inbox.take(until: id).last) else {
                Issue.record("No result for \(tile.intent)")
                continue
            }
            #expect(result != .failure("Try “Open Canvas”, “Show me dog photos”, or “Make text bigger”."), "\(tile.intent) was not routed")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelNeverExecutesAndApprovalRunsExactlyOnce() async throws {
        let (session, inbox) = try start()
        defer { session.stop() }
        var model = InteractionModel(tag: "it")
        model.connected()

        func run(_ effects: [Effect]) async throws {
            guard case .send(let request) = try #require(effects.first) else { return }
            try session.send(request)
            for message in await inbox.take(until: request.requestId) { _ = model.receive(message) }
        }

        try await run(model.submit(.text("Delete everything in Downloads")))
        let prompt = try #require(model.pendingConfirmation)
        #expect(prompt.risk == .destructive)
        try await run(model.decide(approved: false))
        #expect(model.phase == .done("Nothing was changed.", cancelled: true))

        try await run(model.submit(.text("Delete everything in Downloads")))
        _ = try #require(model.pendingConfirmation)
        try await run(model.decide(approved: true))
        #expect(model.phase == .done("Practice deletion finished. No files were touched.", cancelled: false))

        // Reusing the approved ID straight through the transport must fail.
        try session.send(.confirm(requestId: "reuse", confirmationId: prompt.id, approved: true))
        #expect(await inbox.take(until: "reuse").last
            == .result(requestId: "reuse", .failure("Confirmation is missing, expired, or already used.")))

        try session.send(.getHistory(requestId: "history"))
        guard case .history(_, let entries) = try #require(await inbox.take(until: "history").last) else {
            Issue.record("Expected history")
            return
        }
        #expect(entries.filter { $0.action.app == "Mock deletion executor" }.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func closingStdinEndsTheSession() async throws {
        let (session, inbox) = try start()
        session.stop(grace: .seconds(5))
        _ = await inbox.take(until: "never")
        #expect(inbox.terminated)
        #expect(!session.isRunning)
    }
}
