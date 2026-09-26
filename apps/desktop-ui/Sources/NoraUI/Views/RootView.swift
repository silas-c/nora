import NoraCore
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @FocusState private var focus: FocusTarget?

    var body: some View {
        let scale = CGFloat(model.settings.scale)
        let confirming = model.interaction.pendingConfirmation != nil
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14 * scale) {
                    HeaderView(model: model)
                    if model.mode == .live && !model.accessibilityTrusted {
                        PermissionBanner(model: model)
                    }
                    StatusCard(model: model, focus: $focus)
                    TileGrid(model: model, focus: $focus)
                    TextRequestBar(model: model, focus: $focus)
                    CostBar(model: model)
                }
                .padding(.horizontal, 22 * scale)
                .padding(.top, 34)
                .padding(.bottom, 22 * scale)
            }
            // While a confirmation is open, everything behind it is out of reach for pointer, keyboard, and VoiceOver.
            .disabled(confirming)
            .accessibilityHidden(confirming)

            if let prompt = model.interaction.pendingConfirmation {
                ConfirmOverlay(model: model, prompt: prompt, focus: $focus)
            }
        }
        .frame(minWidth: 540 * scale, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.noraScale, scale)
        .onChange(of: focus) { _, newValue in model.currentFocus = newValue }
        .onChange(of: model.requestedFocus) { _, target in
            guard let target else { return }
            focus = target
            model.requestedFocus = nil
        }
    }
}

struct HeaderView: View {
    let model: AppModel
    @Environment(\.noraScale) private var scale

    var body: some View {
        HStack(alignment: .center, spacing: 10 * scale) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text("Nora")
                    .font(.nora(30, .heavy, scale: scale))
                    .accessibilityAddTraits(.isHeader)
                ModeBadge(mode: model.mode)
            }
            Spacer(minLength: 8)
            ActionButton(title: "Activity", symbol: "list.bullet.rectangle.portrait", style: .chip,
                         hint: "Shows what Nora sent, what the agent answered, and what it did") { model.openTransparency() }
            ActionButton(title: "Settings", symbol: "gearshape.fill", style: .chip) { model.openSettings() }
        }
    }
}

struct ModeBadge: View {
    let mode: AgentMode
    @Environment(\.noraScale) private var scale

    var body: some View {
        let practice = mode == .mock
        Label(practice ? "Practice mode · nothing on this Mac changes" : "Live · Nora controls this Mac",
              systemImage: practice ? "shield.lefthalf.filled" : "bolt.fill")
            .font(.nora(14, .bold, scale: scale))
            .foregroundStyle(Color(practice ? Palette.info : Palette.attention))
    }
}

struct PermissionBanner: View {
    let model: AppModel
    @Environment(\.noraScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 12 * scale) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 24 * scale, weight: .bold))
                .foregroundStyle(Color(Palette.attention))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text("Nora needs permission to control apps")
                    .font(.nora(19, .bold, scale: scale))
                Text("Turn on Nora in System Settings › Privacy & Security › Accessibility. Opening apps and websites works without it; zoom and Canvas navigation need it.")
                    .font(.nora(16, scale: scale))
                    .fixedSize(horizontal: false, vertical: true)
                ActionButton(title: "Open Accessibility Settings", symbol: "gearshape", style: .prominent) {
                    model.requestAccessibilityPermission()
                }
            }
        }
        .padding(16 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16 * scale).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16 * scale).strokeBorder(Color(Palette.attention), lineWidth: 2 * scale))
        .accessibilityElement(children: .contain)
    }
}
