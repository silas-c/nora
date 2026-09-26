import AppKit
import NoraCore
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Resolves per appearance so each status color keeps its tested contrast in light and dark mode.
    init(_ pair: Palette.Pair) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = dark ? pair.dark : pair.light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

private struct ScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// In-app text and target scaling. macOS has no system-wide Dynamic Type, so Nora provides its own up to 200%.
    var noraScale: CGFloat {
        get { self[ScaleKey.self] }
        set { self[ScaleKey.self] = newValue }
    }
}

extension Font {
    static func nora(_ size: CGFloat, _ weight: Font.Weight = .regular, scale: CGFloat) -> Font {
        .system(size: size * scale, weight: weight)
    }
}

struct SectionLabel: View {
    let text: String
    @Environment(\.noraScale) private var scale

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.nora(16, .semibold, scale: scale))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Two-tone focus ring (dark outer, light inner) that stays visible on any tile or background.
struct FocusRing: View {
    var cornerRadius: CGFloat
    var visible: Bool
    @Environment(\.noraScale) private var scale

    var body: some View {
        if visible {
            RoundedRectangle(cornerRadius: cornerRadius + 5 * scale, style: .continuous)
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor).opacity(1), lineWidth: 4 * scale)
                .padding(-7 * scale)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius + 2 * scale, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2 * scale)
                        .padding(-3 * scale))
                .allowsHitTesting(false)
        }
    }
}
