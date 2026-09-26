import Foundation

/// One observed request, for the demo evaluation in issue #10. Kept in memory until exported.
public struct EvaluationRecord: Sendable, Equatable, Identifiable {
    public var id: Int
    public var timestamp: Date
    public var modality: String
    public var request: String
    public var intent: String?
    public var outcome: Outcome
    public var agentSeconds: Double
    public var noraActions: Int
    /// Failed or misunderstood attempts immediately before this one.
    public var reformulations: Int
    public var manualActions: Int?
    public var manualSeconds: Double?
}

public struct EvaluationLog: Sendable {
    public private(set) var records: [EvaluationRecord] = []
    private var attemptsSinceSuccess = 0

    public init() {}

    @discardableResult
    public mutating func record(_ completed: CompletedRequest, modality: String, request: String,
                                intent: String?, noraActions: Int) -> EvaluationRecord {
        let manual = intent.flatMap(InteractionCost.baseline(for:))
        let record = EvaluationRecord(
            id: records.count + 1,
            timestamp: completed.finishedAt,
            modality: modality,
            request: request,
            intent: intent,
            outcome: completed.outcome,
            agentSeconds: completed.finishedAt.timeIntervalSince(completed.startedAt),
            noraActions: noraActions,
            reformulations: attemptsSinceSuccess,
            manualActions: manual?.actions,
            manualSeconds: manual?.seconds)
        records.append(record)
        switch completed.outcome {
        case .succeeded, .cancelled: attemptsSinceSuccess = 0
        case .failed, .notUnderstood, .expired: attemptsSinceSuccess += 1
        }
        return record
    }

    public mutating func clear() {
        records.removeAll()
        attemptsSinceSuccess = 0
    }

    public func csv() -> String {
        let formatter = ISO8601DateFormatter()
        let header = "id,timestamp,modality,request,intent,outcome,seconds_to_result,nora_actions,reformulations,manual_actions_klm,manual_seconds_klm"
        let rows = records.map { record in
            [
                String(record.id),
                formatter.string(from: record.timestamp),
                record.modality,
                record.request,
                record.intent ?? "",
                record.outcome.rawValue,
                String(format: "%.2f", record.agentSeconds),
                String(record.noraActions),
                String(record.reformulations),
                record.manualActions.map(String.init) ?? "",
                record.manualSeconds.map { String(format: "%.2f", $0) } ?? "",
            ].map(Self.escape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
