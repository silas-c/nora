import AppKit
import SwiftUI

/// The compact surface for voice and task progress. The full panel opens only when requested.
struct VoiceIndicatorView: View {
    let model: AppModel
    let expand: () -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = StatusPresentation(model: model)
        let listening = model.voice.isListening
        let title = model.voice.isStarting ? "Getting microphone ready…" : listening ? "Listening…" : status.title
        let detail = model.voice.isStarting ? "One moment" : listening && !model.voice.liveTranscript.isEmpty ? model.voice.liveTranscript
            : status.message == "Working on it…" ? model.currentRequestLabel ?? status.message : status.message

        HStack(spacing: 12) {
            if case .listening(let level) = model.voice.state {
                NotchWaveform(level: level)
            } else {
                Image(systemName: status.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(status.color)
                    .frame(width: 28, height: 28)
                    .symbolEffect(.variableColor.iterative, options: status.busy && !reduceMotion ? .repeating : .default)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: expand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Open Nora's full panel")
            .help("Open Nora")

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Hide Nora")
            .help("Hide Nora")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(width: 440, height: 72)
        .background(.regularMaterial, in: UnevenRoundedRectangle(
            topLeadingRadius: 10, bottomLeadingRadius: 23, bottomTrailingRadius: 23, topTrailingRadius: 10))
        .shadow(color: .black.opacity(0.17), radius: 18, y: 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: detail)
        .accessibilityElement(children: .contain)
    }
}

private struct NotchWaveform: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(Color.blue)
                    .frame(width: 3, height: 7 + 21 * level * [0.45, 0.8, 1, 0.7, 0.5][index])
            }
        }
        .frame(width: 28, height: 28)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

final class VoiceIndicatorPanel: NSPanel {
    init(model: AppModel, expand: @escaping () -> Void, dismiss: @escaping () -> Void) {
        let size = NSSize(width: 440, height: 72)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        let host = FirstClickHostingView(rootView: VoiceIndicatorView(model: model, expand: expand, dismiss: dismiss))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
