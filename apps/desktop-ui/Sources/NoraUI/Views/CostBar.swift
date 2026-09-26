import NoraCore
import SwiftUI

/// Compares each finished task with the usual mouse-and-keyboard route, using the Keystroke-Level Model.
struct CostBar: View {
    let model: AppModel
    @Environment(\.noraScale) private var scale
    @State private var expanded = false

    var body: some View {
        let tally = model.tally
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(alignment: .center, spacing: 10 * scale) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 20 * scale, weight: .semibold))
                    .foregroundStyle(Color(Palette.info))
                    .accessibilityHidden(true)
                SectionLabel("Effort")
                Spacer(minLength: 0)
                ActionButton(title: expanded ? "Hide details" : "How is this measured?", symbol: "info.circle", style: .chip) {
                    expanded.toggle()
                }
            }
            if tally.tasks == 0 {
                Text("After your first request, Nora compares it with doing the same task the usual way.")
                    .font(.nora(16, scale: scale))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(tally.noraActions) \(tally.noraActions == 1 ? "press" : "presses") in Nora instead of about \(tally.manualActions) the usual way. \(Self.timeSummary(tally.secondsSaved))")
                    .font(.nora(17, .semibold, scale: scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let last = tally.last {
                Text(Self.lastSummary(last))
                    .font(.nora(15, scale: scale))
                    .fixedSize(horizontal: false, vertical: true)
                if let note = last.manual.note {
                    Text(note)
                        .font(.nora(15, .medium, scale: scale))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    Text("Estimates use the Keystroke-Level Model (Card, Moran & Newell, 1983): 0.28 s per keystroke, 1.1 s to point, 0.2 s per click, 0.4 s to move a hand between mouse and keyboard, and 1.35 s to decide each step. “Time to result” is measured by Nora. This is a demo estimate, not a formal study.")
                        .fixedSize(horizontal: false, vertical: true)
                    if let last = tally.last {
                        Text("The usual way for \(TileCatalog.tile(for: last.intent)?.title ?? last.intent):")
                            .fontWeight(.bold)
                        ForEach(Array(last.manual.steps.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)")
                        }
                    }
                }
                .font(.nora(15, scale: scale))
            }
        }
        .padding(.top, 12 * scale)
        .padding(.bottom, 6 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    static func timeSummary(_ secondsSaved: Double) -> String {
        let seconds = Int(abs(secondsSaved).rounded())
        if seconds == 0 { return "About the same time as the usual way (estimate)." }
        return secondsSaved > 0
            ? "About \(seconds) seconds saved (estimate)."
            : "About \(seconds) seconds slower than the usual way (estimate)."
    }

    static func lastSummary(_ last: TallyEntry) -> String {
        let title = TileCatalog.tile(for: last.intent)?.title ?? last.intent
        let manual = last.manual
        var parts: [String] = []
        if manual.clicks > 0 { parts.append("\(manual.clicks) click\(manual.clicks == 1 ? "" : "s")") }
        if manual.keystrokes > 0 { parts.append("\(manual.keystrokes) key\(manual.keystrokes == 1 ? "" : "s")") }
        let resultTime = String(format: "%.1f", last.agentSeconds)
        return "Last: \(title) took \(last.noraActions) \(last.noraActions == 1 ? "press" : "presses") in Nora, versus \(parts.joined(separator: " and ")) the usual way. Time to result: \(resultTime) s."
    }
}
