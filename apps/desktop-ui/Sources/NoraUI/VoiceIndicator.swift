import AppKit
import SwiftUI

/// A small, click-through status pill below the menu bar. The main panel remains the voice control.
struct VoiceIndicatorView: View {
    let voice: VoiceInput

    private var message: String {
        switch voice.state {
        case .listening: "Listening… speak now"
        case .transcribing: "Turning speech into text…"
        case .failed(.nothingHeard): "I didn’t catch that · try again"
        case .failed: "Voice needs attention in Nora"
        case .idle: voice.recentTranscript.isEmpty ? "Nora · press the mic to speak" : "Heard: \(voice.recentTranscript)"
        }
    }

    private var symbol: String {
        switch voice.state {
        case .listening: "waveform"
        case .transcribing: "text.bubble"
        case .failed: "mic.slash"
        case .idle: voice.recentTranscript.isEmpty ? "mic" : "checkmark"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(voice.isListening ? Color.blue : Color.primary)
                .frame(width: 19)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if case .transcribing = voice.state {
                ProgressView().controlSize(.mini)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 17)
        .frame(width: 352, height: 46)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.13), radius: 14, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }
}

final class VoiceIndicatorPanel: NSPanel {
    init(voice: VoiceInput) {
        let size = NSSize(width: 352, height: 46)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: VoiceIndicatorView(voice: voice))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
