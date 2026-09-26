import NoraCore
import SwiftUI

struct TileGrid: View {
    let model: AppModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale

    var body: some View {
        let rows = TileCatalog.scanRows
        VStack(alignment: .leading, spacing: 9 * scale) {
            SectionLabel("Quick actions")
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex == rows.count - 1 {
                    SectionLabel("Text size")
                        .padding(.top, 6 * scale)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 27 * scale, style: .continuous)
                        .strokeBorder(Color(hex: Palette.scanHighlight), lineWidth: model.scanner.isRowHighlighted(rowIndex) ? 6 * scale : 0)
                        .allowsHitTesting(false))
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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let radius = 17 * scale
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if compact {
                HStack(spacing: 9 * scale) {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 19 * scale, weight: .medium))
                    Text(tile.title)
                        .font(.nora(17, .semibold, scale: scale))
                        .lineLimit(1)
                }
            } else {
                VStack(spacing: 5 * scale) {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 27 * scale, weight: .medium))
                        .foregroundStyle(tile.intent == "OPEN_SCHOOL" ? Color.accentColor : Color.primary)
                        .frame(height: 34 * scale)
                    Text(tile.title)
                        .font(.nora(19, .semibold, scale: scale))
                        .lineLimit(1)
                    Text(tile.detail)
                        .font(.nora(12, scale: scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .padding(8 * scale)
        .frame(maxWidth: .infinity, minHeight: (compact ? 55 : 116) * scale)
        .background(shape.fill(tile.intent == "OPEN_SCHOOL" ? Color.accentColor.opacity(hovered ? 0.19 : 0.12) : Color(nsColor: .controlBackgroundColor).opacity(hovered ? 1 : 0.72)))
        .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.55 : 0.10), lineWidth: (contrast == .increased ? 2 : 1) * scale))
        .overlay(alignment: .topLeading) {
            Text(tile.shortcut)
                .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 2 * scale)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .padding(7 * scale)
        }
        .overlay {
            if let dwellStart {
                DwellRing(start: dwellStart, seconds: dwellSeconds, stepped: reduceMotion)
            }
        }
        .overlay {
            if scanHighlighted {
                shape.strokeBorder(Color(hex: Palette.scanHighlight), lineWidth: 7 * scale)
                    .overlay(shape.inset(by: 7 * scale).strokeBorder(Color.black, lineWidth: 2 * scale))
            }
        }
        .overlay(FocusRing(cornerRadius: radius, visible: isFocused))
        .opacity(enabled ? 1 : 0.42)
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
            ZStack {
                Circle().stroke(Color.primary.opacity(0.18), lineWidth: 8 * scale)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8 * scale, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 60 * scale, height: 60 * scale)
            .padding(8 * scale)
            .background(Circle().fill(.regularMaterial))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
