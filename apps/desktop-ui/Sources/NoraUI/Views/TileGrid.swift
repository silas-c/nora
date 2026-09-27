import NoraCore
import SwiftUI

struct TileGrid: View {
    let model: AppModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale

    var body: some View {
        let rows = TileCatalog.scanRows
        VStack(alignment: .leading, spacing: 9 * scale) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex == rows.count - 1 {
                    SectionLabel("Text size")
                        .padding(.top, 3 * scale)
                }
                HStack(spacing: 10 * scale) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { column, tile in
                        TileView(tile: tile, compact: rowIndex == rows.count - 1, model: model)
                            .focused(focus, equals: .tile(tile.id))
                            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                                move(fromRow: rowIndex, column: column, key: press.key)
                                return .handled
                            }
                    }
                }
                .padding(5 * scale)
                .background(RoundedRectangle(cornerRadius: 27 * scale, style: .continuous)
                    .fill(Color(hex: Palette.scanHighlight).opacity(model.scanner.isRowHighlighted(rowIndex) ? 0.22 : 0)))
            }
        }
    }

    /// Arrow keys move spatially through the grid, the same layout switch scanning follows.
    private func move(fromRow row: Int, column: Int, key: KeyEquivalent) {
        let rows = TileCatalog.scanRows
        var targetRow = row
        var targetColumn = column
        switch key {
        case .leftArrow: targetColumn = max(0, column - 1)
        case .rightArrow: targetColumn = min(rows[row].count - 1, column + 1)
        case .upArrow: targetRow = max(0, row - 1)
        case .downArrow: targetRow = min(rows.count - 1, row + 1)
        default: break
        }
        targetColumn = min(targetColumn, rows[targetRow].count - 1)
        focus.wrappedValue = .tile(rows[targetRow][targetColumn].id)
    }
}

struct TileView: View {
    let tile: TileSpec
    let compact: Bool
    let model: AppModel
    @State private var hovered = false

    var body: some View {
        let enabled = model.interaction.acceptsInput
        TileFace(tile: tile, compact: compact, enabled: enabled,
                 hovered: hovered,
                 scanHighlighted: model.scanner.isHighlighted(tile),
                 dwellStart: model.dwellTarget == tile.id ? model.dwellStartedAt : nil,
                 dwellSeconds: model.settings.dwellSeconds)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { model.activate(tile) } }
            .onHover { hovered = $0; model.hover(tile, inside: $0) }
            .focusable(enabled)
            .focusEffectDisabled()
            .onKeyPress(.return) { activate(enabled) }
            .onKeyPress(.space) { activate(enabled) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tile.title)
            .accessibilityHint("\(tile.detail). Keyboard shortcut \(Self.spoken(tile.shortcut)).")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { model.activate(tile) } }
            .help("\(tile.detail) (press \(tile.shortcut))")
    }

    private func activate(_ enabled: Bool) -> KeyPress.Result {
        guard enabled else { return .ignored }
        model.activate(tile, via: "keyboard")
        return .handled
    }

    private static func spoken(_ shortcut: String) -> String {
        switch shortcut {
        case "-": "minus"
        case "=": "equals"
        default: shortcut
        }
    }
}

private struct TileFace: View {
    let tile: TileSpec
    let compact: Bool
    let enabled: Bool
    let hovered: Bool
    let scanHighlighted: Bool
    let dwellStart: Date?
    let dwellSeconds: Double
    @Environment(\.isFocused) private var isFocused
    @Environment(\.noraScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let radius = 17 * scale
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        HStack(spacing: 12 * scale) {
            Image(systemName: tile.symbol)
                .font(.system(size: 22 * scale, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 43 * scale, height: 43 * scale)
                .background(RoundedRectangle(cornerRadius: 11 * scale, style: .continuous)
                    .fill(iconColor.opacity(0.13)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(tile.title)
                    .font(.nora(15, .semibold, scale: scale))
                    .lineLimit(1)
                Text(tile.detail)
                    .font(.nora(11, scale: scale))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 13 * scale)
        .frame(maxWidth: .infinity, minHeight: (compact ? 70 : 82) * scale)
        .modifier(NoraGlass(shape: shape, interactive: true))
        .overlay(shape.fill(Color.accentColor.opacity(hovered ? 0.08 : 0)).allowsHitTesting(false))
        .overlay {
            if let dwellStart {
                DwellRing(start: dwellStart, seconds: dwellSeconds, stepped: reduceMotion)
            }
        }
        .overlay {
            if scanHighlighted {
                shape.fill(Color(hex: Palette.scanHighlight).opacity(0.22)).allowsHitTesting(false)
            }
        }
        .overlay(FocusRing(cornerRadius: radius, visible: isFocused))
        .opacity(enabled ? 1 : 0.42)
    }

    private var iconColor: Color {
        switch tile.intent {
        case "OPEN_SCHOOL": .blue
        case "OPEN_COURSES": .indigo
        case "OPEN_PHOTOS": .pink
        case "OPEN_DOG_PHOTOS": .orange
        case "OPEN_INTERNET": .cyan
        case "OPEN_FINDER": .teal
        default: .blue
        }
    }
}

/// Shows how long until a dwell selection fires, so resting on a tile is never a surprise.
private struct DwellRing: View {
    let start: Date
    let seconds: Double
    let stepped: Bool
    @Environment(\.noraScale) private var scale

    var body: some View {
        TimelineView(.animation(minimumInterval: stepped ? 0.25 : 1.0 / 30)) { context in
            let progress = min(1, max(0, context.date.timeIntervalSince(start) / seconds))
            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor)
                            .frame(width: geometry.size.width * progress)
                    }
            }
            .frame(width: 80 * scale, height: 8 * scale)
            .padding(8 * scale)
            .background(.regularMaterial, in: Capsule())
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
