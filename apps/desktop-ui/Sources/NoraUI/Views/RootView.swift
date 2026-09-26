import NoraCore
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @FocusState private var focus: FocusTarget?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let scale = CGFloat(model.settings.scale)
        let confirming = model.interaction.pendingConfirmation != nil
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15 * scale) {
                    HeaderView(model: model)
                    if model.mode == .live && !model.accessibilityTrusted {
                        PermissionBanner(model: model)
                    }
                    StatusCard(model: model, focus: $focus)
                    TextRequestBar(model: model, focus: $focus)
                    TileGrid(model: model, focus: $focus)
                    CostBar(model: model)
                }
                .padding(.horizontal, 24 * scale)
                .padding(.top, 28)
                .padding(.bottom, 24 * scale)
            }
            // While a confirmation is open, everything behind it is out of reach for pointer, keyboard, and VoiceOver.
            .disabled(confirming)
            .accessibilityHidden(confirming)

            if let prompt = model.interaction.pendingConfirmation {
                ConfirmOverlay(model: model, prompt: prompt, focus: $focus)
            }
        }
        .frame(minWidth: 560 * scale, minHeight: 620)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else { Color.clear }
        }
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
        HStack(alignment: .center, spacing: 12 * scale) {
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text("Nora")
                    .font(.nora(28, .semibold, scale: scale))
                    .accessibilityAddTraits(.isHeader)
                ModeBadge(mode: model.mode)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8 * scale) {
                ToolbarControl(title: "Activity", symbol: "clock.arrow.circlepath") { model.openTransparency() }
                ToolbarControl(title: "Settings", symbol: "slider.horizontal.3") { model.openSettings() }
            }
        }
    }
}

private struct ToolbarControl: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
        .accessibilityLabel(title)
        .help(title)
        if #available(macOS 26, *) {
            button.glassEffect(.regular.interactive(), in: Circle())
        } else {
            button.background(.regularMaterial, in: Circle())
        }
    }
}

struct ModeBadge: View {
    let mode: AgentMode
    @Environment(\.noraScale) private var scale

    var body: some View {
        let practice = mode == .mock
        Label(practice ? "Practice · no changes" : "Live on this Mac",
              systemImage: practice ? "checkmark.shield" : "circle.fill")
            .font(.nora(12, .medium, scale: scale))
            .foregroundStyle(Color.primary.opacity(0.8))
            .padding(.horizontal, 9 * scale)
            .padding(.vertical, 5 * scale)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .accessibilityHint(practice ? "Actions use a synthetic computer and do not change this Mac" : "Nora can control this Mac")
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
