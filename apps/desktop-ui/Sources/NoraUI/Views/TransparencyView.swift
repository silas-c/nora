import NoraCore
import SwiftUI

/// Shows exactly what Nora sent, what the agent answered, and what it actually did. No black box.
struct TransparencyView: View {
    let model: AppModel

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Right now") {
                    row("Mode", model.mode == .mock ? "Practice (synthetic Canvas controller, nothing on this Mac changes)" : "Live (Swift helper controls this Mac)")
                    row("Agent", model.agentPID.map { "Running, process \($0)" } ?? "Not running")
                    row("Routing", "Exact built-in phrases run locally; other requests use Jev and DeepSeek when configured.")
                    row("Spoken feedback", model.settings.spokenFeedback ? model.speaker.lastEngine.rawValue : "Off")
                    row("Offline phrases", "\(model.speaker.cachedCount) of \(model.speaker.knownPhraseCount) ready")
                    if !model.voice.lastEngine.isEmpty { row("Speech recognition", model.voice.lastEngine) }
                }

                CostBar(model: model)

                section("Actions the agent ran") {
                    HStack(spacing: 8) {
                        ActionButton(title: "Refresh", symbol: "arrow.clockwise", style: .chip) { model.refreshHistory() }
                        ActionButton(title: "Clear", symbol: "trash", style: .chip) { model.clearHistory() }
                    }
                    Text("The agent keeps a redacted record: typed text is hidden and web addresses keep only the site.")
                        .font(.callout)
                    if model.history.isEmpty {
                        Text("No actions yet.").foregroundStyle(.primary)
                    }
                    ForEach(model.history) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(Color(entry.success ? Palette.success : Palette.failure))
                                .accessibilityLabel(entry.success ? "Succeeded" : "Failed")
                            Text(Self.clock.string(from: entry.startedAt)).monospacedDigit()
                            Text(ActionDescriber.describe(entry.action))
                            Spacer()
                            Text("\(Int(entry.duration * 1000)) ms").monospacedDigit()
                        }
                        .font(.system(size: 13))
                    }
                }

                section("Evaluation log") {
                    Text("Each request: how it was made, the outcome, time to result, presses in Nora, and how many tries it took. Stays on this Mac until you save it.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        ActionButton(title: "Save as CSV", symbol: "square.and.arrow.down", style: .chip, enabled: !model.evaluation.records.isEmpty) {
                            model.exportEvaluation()
                        }
                        if model.exportedEvaluation != nil {
                            ActionButton(title: "Show in Finder", symbol: "folder", style: .chip) { model.revealExport() }
                        }
                        ActionButton(title: "Reset", symbol: "arrow.counterclockwise", style: .chip) { model.resetMeasurements() }
                    }
                    ForEach(model.evaluation.records.reversed()) { record in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("#\(record.id)").monospacedDigit()
                            Text(record.modality).fontWeight(.semibold)
                            Text("“\(record.request)”").lineLimit(1)
                            Spacer()
                            Text(record.outcome.rawValue)
                            Text(String(format: "%.2f s", record.agentSeconds)).monospacedDigit()
                            Text("\(record.noraActions) press\(record.noraActions == 1 ? "" : "es")")
                            if record.reformulations > 0 { Text("\(record.reformulations) retr\(record.reformulations == 1 ? "y" : "ies")") }
                        }
                        .font(.system(size: 13))
                    }
                }

                section("Permission check") {
                    Text("Confirms that macOS charges the Nora → node → helper chain to Nora, so one Accessibility permission covers everything.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Run check", symbol: "checkmark.shield", style: .chip) { model.runPermissionCheck() }
                    if let report = model.permissionReport {
                        Text(report.summary).fixedSize(horizontal: false, vertical: true)
                        Text("Nora process \(report.noraPID); chain charged to process \(report.chainResponsiblePID.map(String.init) ?? "unknown") \(report.chainResponsiblePath ?? "")")
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                section("Messages between Nora and its agent") {
                    if model.trace.isEmpty { Text("Nothing yet.") }
                    ForEach(model.trace.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(Self.clock.string(from: entry.time)).monospacedDigit()
                                Text(entry.direction.rawValue).fontWeight(.bold)
                                    .accessibilityLabel(Self.directionName(entry.direction))
                                Text(entry.summary).fontWeight(.semibold)
                            }
                            if !entry.raw.isEmpty && entry.raw != entry.summary {
                                Text(entry.raw)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(4)
                                    .textSelection(.enabled)
                            }
                        }
                        .font(.system(size: 13))
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).fontWeight(.semibold).frame(width: 150, alignment: .leading)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 14))
        .accessibilityElement(children: .combine)
    }

    private static func directionName(_ direction: TraceEntry.Direction) -> String {
        switch direction {
        case .sent: "Sent"
        case .received: "Received"
        case .diagnostic: "Agent log"
        case .note: "Note"
        }
    }
}
