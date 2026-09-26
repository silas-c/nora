import Foundation
import Testing
@testable import NoraCore

@Suite("Agent protocol")
struct ProtocolTests {
    private func line(_ request: AgentRequest) throws -> String {
        String(decoding: try AgentCodec.encodeLine(request), as: UTF8.self)
    }

    private func decode(_ json: String) throws -> AgentMessage {
        try AgentCodec.decode(line: Data(json.utf8))
    }

    @Test func schoolTileEncodesTheIssueThreeInput() throws {
        let encoded = try line(.submit(requestId: "aac-1", input: .aac("OPEN_SCHOOL")))
        #expect(encoded == #"{"input":{"intent":"OPEN_SCHOOL","source":"aac"},"requestId":"aac-1","type":"submit"}"# + "\n")
    }

    @Test func textAndVoiceInputsCarryTheirWords() throws {
        #expect(try line(.submit(requestId: "t", input: .text("Open Canvas")))
            == #"{"input":{"source":"text","text":"Open Canvas"},"requestId":"t","type":"submit"}"# + "\n")
        #expect(try line(.submit(requestId: "v", input: .voice("open canvas")))
            == #"{"input":{"source":"voice","text":"open canvas"},"requestId":"v","type":"submit"}"# + "\n")
    }

    @Test func decisionsAndHistoryRequestsMatchTheTransport() throws {
        #expect(try line(.confirm(requestId: "d", confirmationId: "c-1", approved: false))
            == #"{"approved":false,"confirmationId":"c-1","requestId":"d","type":"confirm"}"# + "\n")
        #expect(try line(.getHistory(requestId: "h")) == #"{"requestId":"h","type":"get_history"}"# + "\n")
        #expect(try line(.clearHistory(requestId: "h2")) == #"{"requestId":"h2","type":"clear_history"}"# + "\n")
    }

    @Test func typedNewlinesNeverBreakFraming() throws {
        let encoded = try AgentCodec.encodeLine(.submit(requestId: "t", input: .text("open\ncanvas")))
        #expect(encoded.filter { $0 == 0x0A }.count == 1)
    }

    @Test func decodesStatusEventsAndResults() throws {
        #expect(try decode(#"{"type":"event","requestId":"r","event":{"type":"thinking"}}"#) == .event(requestId: "r", .thinking(nil)))
        #expect(try decode(#"{"type":"event","requestId":"r","event":{"type":"acting","message":"Opening Canvas in Microsoft Edge…"}}"#)
            == .event(requestId: "r", .acting("Opening Canvas in Microsoft Edge…")))
        #expect(try decode(#"{"type":"result","requestId":"r","result":{"success":true,"message":"ok"}}"#) == .result(requestId: "r", .success("ok")))
        #expect(try decode(#"{"type":"result","requestId":"r","result":{"success":false,"error":"nope"}}"#) == .result(requestId: "r", .failure("nope")))
        #expect(try decode(#"{"type":"protocol_error","requestId":null,"error":"bad"}"#) == .protocolError(requestId: nil, "bad"))
    }

    @Test func decodesConfirmationPromptWithExactAction() throws {
        let json = #"{"type":"event","requestId":"r","event":{"type":"confirmation_required","confirmationId":"c-1","action":{"type":"launch_app","app":"Mock deletion executor"},"risk":"destructive","expiresAt":1790458172127,"message":"Delete it Action: {}"}}"#
        guard case .event("r", .confirmationRequired(let prompt)) = try decode(json) else {
            Issue.record("Expected a confirmation prompt")
            return
        }
        #expect(prompt.id == "c-1")
        #expect(prompt.risk == .destructive)
        #expect(prompt.action == ComputerAction(type: "launch_app", app: "Mock deletion executor"))
        #expect(prompt.expiresAt == Date(timeIntervalSince1970: 1790458172.127))
    }

    @Test func pendingResultIsNotAFailure() throws {
        let json = #"{"type":"result","requestId":"r","result":{"success":false,"requiresConfirmation":true,"confirmationId":"c-1","message":"m"}}"#
        #expect(try decode(json) == .result(requestId: "r", .needsConfirmation(id: "c-1", message: "m")))
    }

    @Test func unknownRiskIsNeverSafe() throws {
        let json = #"{"type":"event","requestId":"r","event":{"type":"confirmation_required","confirmationId":"c","action":{"type":"x"},"risk":"weird","expiresAt":0,"message":"m"}}"#
        guard case .event(_, .confirmationRequired(let prompt)) = try decode(json) else {
            Issue.record("Expected a confirmation prompt")
            return
        }
        #expect(prompt.risk == .sensitive)
    }

    @Test func futureEventTypesDecodeWithoutFailing() throws {
        #expect(try decode(#"{"type":"event","requestId":"r","event":{"type":"progress","percent":50}}"#) == .event(requestId: "r", .unrecognized("progress")))
    }

    @Test func decodesRedactedHistory() throws {
        let json = #"{"type":"history","requestId":"h","entries":[{"id":1,"action":{"type":"open_url","url":"https://canvas.temple.edu","browser":"Microsoft Edge"},"success":true,"timestamp":1000,"completedAt":1250}]}"#
        guard case .history("h", let entries) = try decode(json) else {
            Issue.record("Expected history")
            return
        }
        #expect(entries.count == 1)
        #expect(entries[0].duration == 0.25)
        #expect(entries[0].action.url == "https://canvas.temple.edu")
    }

    @Test func framerHandlesPartialChunksAndCRLF() {
        var framer = LineFramer()
        #expect(framer.append(Data("{\"a\":".utf8)).isEmpty)
        let lines = framer.append(Data("1}\r\n{\"b\":2}\n{\"c\"".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
        #expect(framer.append(Data(":3}\n".utf8)).map { String(decoding: $0, as: UTF8.self) } == [#"{"c":3}"#])
    }
}
