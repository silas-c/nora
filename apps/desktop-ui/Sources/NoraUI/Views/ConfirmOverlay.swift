import NoraCore
import SwiftUI

/// Issue #9: the exact action, its risk, and an explicit Cancel/Confirm choice. Cancel is the default focus.
struct ConfirmOverlay: View {
    let model: AppModel
    let prompt: ConfirmationRequest
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(reduceTransparency ? 0.8 : 0.5)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                ScrollView {
                    dialog
                        .padding(20 * scale)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { focus.wrappedValue = .confirmCancel }
    }

    private var decisionSent: Bool {
        if case .confirming(_, let sent) = model.interaction.phase { return sent }
        return true
    }

    private var dialog: some View {
        let color = Color(prompt.risk == .destructive ? Palette.failure : Palette.attention)
        return VStack(alignment: .leading, spacing: 14 * scale) {
            Label(ActionDescriber.riskTitle(prompt.risk),
                  systemImage: prompt.risk == .destructive ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.nora(18, .heavy, scale: scale))
                .foregroundStyle(color)
            Text("Do you want Nora to do this?")
                .font(.nora(19, .semibold, scale: scale))
            Text(ActionDescriber.headline(prompt))
                .font(.nora(25, .bold, scale: scale))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(ActionDescriber.riskExplanation(prompt.risk))
                .font(.nora(17, scale: scale))
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text("Exact action")
                    .font(.nora(14, .bold, scale: scale))
                    .textCase(.uppercase)
                Text(ActionDescriber.describe(prompt.action))
                    .font(.nora(17, .semibold, scale: scale))
                Text(Self.json(prompt.action))
                    .font(.system(size: 13 * scale, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12 * scale).fill(Color(nsColor: .controlBackgroundColor)))
            Text("Nothing happens unless you choose Confirm. For safety, this question closes by itself after about a minute.")
                .font(.nora(15, scale: scale))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12 * scale) {
                ActionButton(title: "Cancel", symbol: "xmark", style: .neutral, enabled: !decisionSent, hint: "Nothing will be done") {
                    model.decide(approved: false)
                }
                .focused(focus, equals: .confirmCancel)
                ActionButton(title: "Confirm", symbol: "checkmark", style: prompt.risk == .destructive ? .destructive : .prominent,
                             enabled: !decisionSent, hint: "Nora does exactly the action described") {
                    model.decide(approved: true)
                }
                .focused(focus, equals: .confirmApprove)
            }
            if decisionSent {
                Text("Sending your choice…")
                    .font(.nora(15, .semibold, scale: scale))
            }
        }
        .padding(24 * scale)
        .frame(maxWidth: 500 * scale, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 28 * scale, y: 12 * scale)
    }

    private static func json(_ action: ComputerAction) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(action)).map { String(decoding: $0, as: UTF8.self) } ?? action.type
    }
}
