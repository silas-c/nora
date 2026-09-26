import Foundation
import Testing
@testable import NoraCore

@Suite("Interaction model")
struct InteractionModelTests {
    private func connectedModel() -> InteractionModel {
        var model = InteractionModel(tag: "test")
        model.connected()
        return model
    }

    private func sentRequest(_ effects: [Effect]) -> AgentRequest? {
        for effect in effects { if case .send(let request) = effect { return request } }
        return nil
    }

    private func announcements(_ effects: [Effect]) -> [String] {
        effects.compactMap { if case .announce(let text, _) = $0 { text } else { nil } }
    }

    private func confirmation(_ id: String = "c-1") -> ConfirmationRequest {
        ConfirmationRequest(id: id, message: "Delete everything in Downloads Action: {}",
                            action: ComputerAction(type: "launch_app", app: "Mock deletion executor"),
                            risk: .destructive, expiresAt: Date().addingTimeInterval(60))
    }

    @Test func inputIsBlockedUntilTheAgentConnects() {
        var model = InteractionModel(tag: "test")
        #expect(model.submit(.aac("OPEN_SCHOOL")).isEmpty)
        model.connected()
        #expect(model.phase == .idle)
        #expect(sentRequest(model.submit(.aac("OPEN_SCHOOL"))) != nil)
    }

    @Test func schoolTileWalksIdleActingDone() throws {
        var model = connectedModel()
        let request = try #require(sentRequest(model.submit(.aac("OPEN_SCHOOL"))))
        #expect(request == .submit(requestId: request.requestId, input: .aac("OPEN_SCHOOL")))
        #expect(model.isBusy)
        #expect(model.submit(.aac("OPEN_SCHOOL")).isEmpty, "A second press while busy must not submit")

        let id = request.requestId
        _ = model.receive(.event(requestId: id, .thinking(nil)))
        #expect(model.phase == .working(.thinking, "Working on it…"))
        let acting = model.receive(.event(requestId: id, .acting("Opening Canvas in Microsoft Edge…")))
        #expect(model.phase == .working(.acting, "Opening Canvas in Microsoft Edge…"))
        #expect(announcements(acting) == ["Opening Canvas in Microsoft Edge…"])
        let done = model.receive(.event(requestId: id, .done("Canvas open request sent to Microsoft Edge.")))
        #expect(model.phase == .done("Canvas open request sent to Microsoft Edge.", cancelled: false))
        #expect(announcements(done) == ["Canvas open request sent to Microsoft Edge."])

        let finished = model.receive(.result(requestId: id, .success("Canvas open request sent to Microsoft Edge.")))
        #expect(announcements(finished).isEmpty, "The outcome is announced once")
        #expect(finished.contains { if case .completed(let c) = $0 { c.outcome == .succeeded } else { false } })
        #expect(!model.isBusy)
    }

    @Test func eventsForOtherRequestsAreIgnored() throws {
        var model = connectedModel()
        let id = try #require(sentRequest(model.submit(.text("Open Canvas")))).requestId
        #expect(model.receive(.event(requestId: "someone-else", .error("boom"))).isEmpty)
        #expect(model.receive(.result(requestId: "someone-else", .failure("busy"))).isEmpty)
        #expect(model.activeRequestId == id)
    }

    @Test func unknownTextBecomesRepairChoices() throws {
        var model = connectedModel()
        let id = try #require(sentRequest(model.submit(.text("open my canvs")))).requestId
        let hint = "Try “Open Canvas”, “Show me dog photos”, or “Make text bigger”."
        _ = model.receive(.event(requestId: id, .error(hint)))
        let finished = model.receive(.result(requestId: id, .failure(hint)))
        guard case .failed(let failure) = model.phase else {
            Issue.record("Expected a failure phase")
            return
        }
        #expect(failure.kind == .notUnderstood)
        #expect(failure.message == "I’m not sure what “open my canvs” means yet.")
        #expect(failure.suggestions.first?.intent == "OPEN_SCHOOL")
        #expect(finished.contains { if case .completed(let c) = $0 { c.outcome == .notUnderstood } else { false } })
    }

    @Test func helperErrorsAreRewrittenInPlainLanguage() throws {
        var model = connectedModel()
        let id = try #require(sentRequest(model.submit(.aac("OPEN_SCHOOL")))).requestId
        _ = model.receive(.event(requestId: id, .error("Unable to find application named 'Microsoft Edge'")))
        guard case .failed(let failure) = model.phase else {
            Issue.record("Expected a failure phase")
            return
        }
        #expect(failure.message == "Microsoft Edge isn’t installed on this Mac.")
        #expect(failure.detail == "Unable to find application named 'Microsoft Edge'")
    }

    @Test func approvedConfirmationRunsOnce() throws {
        var model = connectedModel()
        let submitId = try #require(sentRequest(model.submit(.text("Delete everything in Downloads")))).requestId
        let prompt = confirmation()
        let asked = model.receive(.event(requestId: submitId, .confirmationRequired(prompt)))
        #expect(model.phase == .confirming(prompt, decisionSent: false))
        #expect(asked.contains { if case .announce(_, true) = $0 { true } else { false } }, "Prompts are announced urgently")
        _ = model.receive(.result(requestId: submitId, .needsConfirmation(id: prompt.id, message: prompt.message)))
        #expect(model.isBusy, "Nothing else can be submitted while a prompt is open")
        #expect(model.submit(.aac("OPEN_SCHOOL")).isEmpty)

        let decision = try #require(sentRequest(model.decide(approved: true)))
        #expect(decision == .confirm(requestId: decision.requestId, confirmationId: "c-1", approved: true))
        #expect(model.decide(approved: true).isEmpty, "A second press cannot send a second approval")
        #expect(model.decide(approved: false).isEmpty)

        _ = model.receive(.event(requestId: submitId, .confirmationResolved(id: "c-1", reason: .approved)))
        #expect(model.pendingConfirmation == nil)
        _ = model.receive(.event(requestId: decision.requestId, .acting("Deleting…")))
        _ = model.receive(.event(requestId: decision.requestId, .done("Practice deletion finished.")))
        let finished = model.receive(.result(requestId: decision.requestId, .success("Practice deletion finished.")))
        #expect(model.phase == .done("Practice deletion finished.", cancelled: false))
        #expect(finished.contains { if case .completed(let c) = $0 { c.outcome == .succeeded } else { false } })
        #expect(model.decide(approved: true).isEmpty, "A resolved prompt cannot be reused")
    }

    @Test func cancelledConfirmationSaysNothingChanged() throws {
        var model = connectedModel()
        let submitId = try #require(sentRequest(model.submit(.aac("SIMULATE_DELETE_DOWNLOADS")))).requestId
        _ = model.receive(.event(requestId: submitId, .confirmationRequired(confirmation())))
        _ = model.receive(.result(requestId: submitId, .needsConfirmation(id: "c-1", message: "m")))
        let decision = try #require(sentRequest(model.decide(approved: false)))
        _ = model.receive(.event(requestId: submitId, .confirmationResolved(id: "c-1", reason: .cancelled)))
        let done = model.receive(.event(requestId: decision.requestId, .done("Cancelled. No action was executed.")))
        #expect(model.phase == .done("Nothing was changed.", cancelled: true))
        #expect(announcements(done) == ["Cancelled. Nothing was changed."])
        let finished = model.receive(.result(requestId: decision.requestId, .success("Cancelled. No action was executed.")))
        #expect(finished.contains { if case .completed(let c) = $0 { c.outcome == .cancelled } else { false } })
        #expect(!model.isBusy)
    }

    @Test func expiryWithoutADecisionOffersAskAgain() throws {
        var model = connectedModel()
        let submitId = try #require(sentRequest(model.submit(.text("Delete everything in Downloads")))).requestId
        _ = model.receive(.event(requestId: submitId, .confirmationRequired(confirmation())))
        _ = model.receive(.result(requestId: submitId, .needsConfirmation(id: "c-1", message: "m")))
        let expired = model.receive(.event(requestId: submitId, .confirmationResolved(id: "c-1", reason: .expired)))
        guard case .failed(let failure) = model.phase else {
            Issue.record("Expected a failure phase")
            return
        }
        #expect(failure.kind == .expired)
        #expect(failure.recovery == .askAgain)
        #expect(expired.contains { if case .completed(let c) = $0 { c.outcome == .expired } else { false } })
        #expect(model.decide(approved: true).isEmpty, "An expired prompt cannot be approved")
        let again = try #require(sentRequest(model.askAgain()))
        #expect(again == .submit(requestId: again.requestId, input: .text("Delete everything in Downloads")))
    }

    @Test func staleDecisionFailureReleasesThePrompt() throws {
        var model = connectedModel()
        let submitId = try #require(sentRequest(model.submit(.text("Delete everything in Downloads")))).requestId
        _ = model.receive(.event(requestId: submitId, .confirmationRequired(confirmation())))
        _ = model.receive(.result(requestId: submitId, .needsConfirmation(id: "c-1", message: "m")))
        let decision = try #require(sentRequest(model.decide(approved: true)))
        _ = model.receive(.result(requestId: decision.requestId, .failure("Confirmation is missing, expired, or already used.")))
        #expect(model.pendingConfirmation == nil)
        #expect(!model.isBusy)
        guard case .failed(let failure) = model.phase else {
            Issue.record("Expected a failure phase")
            return
        }
        #expect(failure.recovery == .askAgain)
    }

    @Test func disconnectClearsEverythingAndBlocksInput() throws {
        var model = connectedModel()
        _ = model.submit(.aac("OPEN_SCHOOL"))
        let effects = model.disconnected(FailureInfo(kind: .connection, message: "Stopped", detail: "exit 1", recovery: .restartAgent))
        #expect(announcements(effects) == ["Stopped"])
        #expect(model.activeRequestId == nil)
        #expect(model.isBusy)
        #expect(model.submit(.aac("OPEN_SCHOOL")).isEmpty)
    }

    @Test func requestIdsAreUniqueAndBounded() throws {
        var model = connectedModel()
        var ids = Set<String>()
        for _ in 0..<50 {
            let id = try #require(sentRequest(model.submit(.aac("ZOOM_IN")))).requestId
            #expect(id.count <= 128)
            ids.insert(id)
            _ = model.receive(.result(requestId: id, .success(nil)))
        }
        #expect(ids.count == 50)
    }
}
