import NoraCore
import SwiftUI

/// A large button that is always reachable by keyboard (Tab, Return, Space), whether or not
/// macOS "Keyboard navigation" is turned on, and that acts on the first click.
struct ActionButton: View {
    enum Style {
        case prominent
        case neutral
        case destructive
        case chip
    }

    let title: String
    var symbol: String?
    var style: Style = .neutral
    var enabled = true
    var hint: String?
    let action: () -> Void

    var body: some View {
        ActionButtonLabel(title: title, symbol: symbol, style: style, enabled: enabled)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .focusable(enabled)
            .focusEffectDisabled()
            .onKeyPress(.return) { run() }
            .onKeyPress(.space) { run() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
    }

    private func run() -> KeyPress.Result {
        guard enabled else { return .ignored }
        action()
        return .handled
    }
}

private struct ActionButtonLabel: View {
    let title: String
    let symbol: String?
    let style: ActionButton.Style
    let enabled: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.noraScale) private var scale

    var body: some View {
        let radius = (style == .chip ? 12 : 15) * scale
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        HStack(spacing: 8 * scale) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: (style == .chip ? 14 : 18) * scale, weight: .medium))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.nora(style == .chip ? 13 : 16, .semibold, scale: scale))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, (style == .chip ? 12 : 16) * scale)
        .frame(minHeight: (style == .chip ? 38 : 48) * scale)
        .background {
            if #available(macOS 26, *), style == .prominent || style == .neutral {
                Color.clear.glassEffect(.regular.tint(style == .prominent ? Color.accentColor : nil).interactive(), in: shape)
            } else {
                shape.fill(background)
            }
        }
        .overlay(FocusRing(cornerRadius: radius, visible: isFocused))
        .opacity(enabled ? 1 : 0.45)
    }

    private var background: Color {
        switch style {
        case .prominent: Color(hex: TileCatalog.home[0].color)
        case .destructive: Color(hex: 0xB3261E)
        case .neutral, .chip: Color(nsColor: .controlBackgroundColor)
        }
    }

    private var foreground: Color {
        switch style {
        case .destructive: .white
        case .prominent:
            if #available(macOS 26, *) { .primary } else { .white }
        case .neutral, .chip: .primary
        }
    }

}

/// Wraps children onto new lines, so example phrases and repair choices never truncate at large text sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: width, height: nil))
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
