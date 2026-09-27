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
                VStack(alignment: .leading, spacing: 16 * scale) {
                    HeaderView(model: model)
                    if model.mode == .live && !model.accessibilityTrusted {
                        PermissionBanner(model: model)
                    }
                    BrandHero()
                    StatusCard(model: model, focus: $focus)
                    TextRequestBar(model: model, focus: $focus)
                    TileGrid(model: model, focus: $focus)
                }
                .padding(.horizontal, 30 * scale)
                .padding(.top, 20)
                .padding(.bottom, 26 * scale)
            }
            // While a confirmation is open, everything behind it is out of reach for pointer, keyboard, and VoiceOver.
            .disabled(confirming)
            .accessibilityHidden(confirming)

            if let prompt = model.interaction.pendingConfirmation {
                ConfirmOverlay(model: model, prompt: prompt, focus: $focus)
            }
        }
        .frame(minWidth: 720 * scale, minHeight: 640)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                LinearGradient(colors: [Color.blue.opacity(0.13), Color.clear, Color.pink.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
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
            HStack(spacing: 8 * scale) {
                NoraOrb(size: 20 * scale)
                Text("Nora")
                    .font(.nora(14, .semibold, scale: scale))
                ModeBadge(mode: model.mode)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8 * scale) {
                ToolbarControl(title: "Activity", symbol: "clock.arrow.circlepath") { model.openTransparency() }
                ToolbarControl(title: "Settings", symbol: "slider.horizontal.3") { model.openSettings() }
                ExamplesMenu(model: model)
            }
        }
    }
}

private struct ExamplesMenu: View {
    let model: AppModel

    var body: some View {
        Menu {
            ForEach(Vocabulary.examples, id: \.self) { phrase in
                Button(phrase) { model.submitExample(phrase) }
                    .disabled(!model.interaction.acceptsInput)
            }
            if model.mode == .mock {
                Divider()
                Button("Safety demo: delete Downloads") { model.submitExample("Delete everything in Downloads") }
                    .disabled(!model.interaction.acceptsInput)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 38, height: 38)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Example requests and practice tools")
        .help("More")
    }
}

private struct BrandHero: View {
    @Environment(\.noraScale) private var scale

    var body: some View {
        VStack(spacing: 4 * scale) {
            HStack(spacing: 12 * scale) {
                NoraOrb(size: 48 * scale)
                Text("Nora")
                    .font(.nora(34, .semibold, scale: scale))
                    .tracking(-1.2 * scale)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text("Your voice. A more independent you.")
                .font(.nora(15, scale: scale))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20 * scale)
        .padding(.bottom, 4 * scale)
    }
}

struct NoraOrb: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.95), Color(red: 0.66, green: 0.79, blue: 1),
                                          Color(red: 0.18, green: 0.50, blue: 1)],
                                 center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
            .shadow(color: .blue.opacity(0.42), radius: size * 0.18)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
        .accessibilityElement(children: .contain)
    }
}
