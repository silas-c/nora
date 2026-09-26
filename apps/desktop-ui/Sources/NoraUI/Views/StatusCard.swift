import NoraCore
import SwiftUI

/// One place that always says what Nora is doing, in large plain language (issue #3: idle, acting, done, error).
struct StatusCard: View {
    let model: AppModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = StatusPresentation(model: model)
        VStack(alignment: .leading, spacing: 14 * scale) {
            HStack(alignment: .top, spacing: 14 * scale) {
                StatusIcon(status: status, reduceMotion: reduceMotion)
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text(status.title)
                        .font(.nora(26, .bold, scale: scale))
                    Text(status.message)
                        .font(.nora(19, .regular, scale: scale))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(status.title). \(status.message)")

            if case .listening(let level) = model.voice.state {
                LevelMeter(level: level)
            }
            StatusActions(model: model, focus: focus)
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).strokeBorder(status.color, lineWidth: 3 * scale))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status.title)
    }
}

struct StatusPresentation {
    var title: String
    var message: String
    var symbol: String
    var color: Color
    var busy = false

    @MainActor
    init(model: AppModel) {
        switch model.voice.state {
        case .listening:
            self.init("Listening…", "Say what you want to do. Nora stops by itself when you pause.", "mic.fill", Color(Palette.info))
            return
        case .transcribing:
            self.init("Writing down what you said…", "One moment.", "waveform", Color(Palette.info), busy: true)
            return
        case .failed(let failure):
            switch failure {
            case .microphoneDenied:
                self.init("Microphone is off", "Allow Nora to use the microphone in System Settings, or type instead.", "mic.slash.fill", Color(Palette.attention))
            case .needsAppBundle:
                self.init("Voice needs the Nora app", "Start Nora with apps/desktop-ui/scripts/run.sh to use the microphone. Typing and tiles work now.", "mic.slash.fill", Color(Palette.attention))
            case .nothingHeard:
                self.init("I didn’t catch that", "You can try again, type it, or choose a picture.", "ear.trianglebadge.exclamationmark", Color(Palette.attention))
            case .service(let detail):
                self.init("Voice didn’t work", detail, "exclamationmark.bubble.fill", Color(Palette.failure))
            }
            return
        case .idle:
            break
        }

        switch model.interaction.phase {
        case .connecting:
            self.init("Starting Nora…", "Connecting to the agent.", "hourglass", Color(Palette.info), busy: true)
        case .idle:
            self.init("Ready", "Choose a picture below, or type what you want.", "hand.wave.fill", Color(Palette.info))
        case .listening(let partial):
            self.init("Listening…", partial ?? "Say what you want to do.", "mic.fill", Color(Palette.info))
        case .working(.thinking, let message):
            self.init("Working on it…", message, "ellipsis.circle.fill", Color(Palette.info), busy: true)
        case .working(.acting, let message):
            self.init("Doing it now", message, "arrow.triangle.2.circlepath", Color(Palette.info), busy: true)
        case .confirming(let prompt, let sent):
            self.init("Waiting for your choice", sent ? "Sending your choice…" : ActionDescriber.headline(prompt), "hand.raised.fill", Color(Palette.attention))
        case .done(let message, false):
            self.init("Done", message, "checkmark.circle.fill", Color(Palette.success))
        case .done(_, true):
            self.init("Cancelled", "Nothing was changed.", "xmark.circle.fill", Color(Palette.info))
        case .failed(let failure):
            switch failure.kind {
            case .notUnderstood:
                self.init("Did you mean…", failure.message, "questionmark.bubble.fill", Color(Palette.attention))
            case .expired:
                self.init("Timed out for safety", failure.message, "clock.badge.exclamationmark.fill", Color(Palette.attention))
            case .actionFailed, .connection:
                self.init("That didn’t work", failure.message, "exclamationmark.triangle.fill", Color(Palette.failure))
            }
        case .disconnected(let failure):
            self.init("Nora’s agent isn’t running", "\(failure.message) \(failure.detail)", "bolt.horizontal.circle.fill", Color(Palette.failure))
        }
    }

    private init(_ title: String, _ message: String, _ symbol: String, _ color: Color, busy: Bool = false) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.color = color
        self.busy = busy
    }
}

private struct StatusIcon: View {
    let status: StatusPresentation
    let reduceMotion: Bool
    @Environment(\.noraScale) private var scale

    var body: some View {
        Group {
            if status.busy && !reduceMotion {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: status.symbol)
                    .font(.system(size: 34 * scale, weight: .bold))
                    .foregroundStyle(status.color)
            }
        }
        .frame(width: 44 * scale, height: 44 * scale)
        .accessibilityHidden(true)
    }
}

private struct LevelMeter: View {
    let level: Double
    @Environment(\.noraScale) private var scale

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule().fill(Color(Palette.info)).frame(width: max(8, geometry.size.width * level))
            }
        }
        .frame(height: 10 * scale)
        .accessibilityHidden(true)
    }
}

/// Recovery is always one press away: repair choices, “ask again”, settings, or restarting the agent.
private struct StatusActions: View {
    let model: AppModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale

    var body: some View {
        switch model.voice.state {
        case .failed(.microphoneDenied):
            FlowLayout(spacing: 8 * scale) {
                ActionButton(title: "Open Microphone Settings", symbol: "gearshape", style: .chip) { model.openMicrophoneSettings() }
                typeInstead
            }
        case .failed(.nothingHeard), .failed(.service):
            FlowLayout(spacing: 8 * scale) {
                ActionButton(title: "Try again", symbol: "mic.fill", style: .chip) { model.toggleVoice() }
                typeInstead
            }
        default:
            phaseActions
        }
    }

    @ViewBuilder
    private var phaseActions: some View {
        switch model.interaction.phase {
        case .failed(let failure):
            FlowLayout(spacing: 8 * scale) {
                ForEach(failure.suggestions) { suggestion in
                    ActionButton(title: suggestion.label, symbol: TileCatalog.tile(for: suggestion.intent)?.symbol, style: .chip,
                                 hint: "Did you mean this? Sends it now.") { model.choose(suggestion) }
                        .focused(focus, equals: .suggestion(suggestion.intent))
                }
                if failure.kind == .notUnderstood {
                    typeInstead
                }
                recovery(failure.recovery)
            }
        case .disconnected(let failure):
            recovery(failure.recovery)
        default:
            EmptyView()
        }
    }

    private var typeInstead: some View {
        ActionButton(title: "Something else", symbol: "keyboard", style: .chip, hint: "Moves to the text box") {
            model.dismiss()
            model.requestedFocus = .textField
        }
    }

    @ViewBuilder
    private func recovery(_ recovery: Recovery?) -> some View {
        switch recovery {
        case .askAgain:
            ActionButton(title: "Ask again", symbol: "arrow.clockwise", style: .chip) { model.askAgain() }
        case .openAccessibilitySettings:
            ActionButton(title: "Open Accessibility Settings", symbol: "gearshape", style: .chip) { model.requestAccessibilityPermission() }
        case .restartAgent:
            ActionButton(title: "Restart Nora’s agent", symbol: "arrow.clockwise", style: .chip) { model.restart() }
        case nil:
            EmptyView()
        }
    }
}
