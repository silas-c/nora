import NoraCore
import SwiftUI

struct TileGrid: View {
    let model: AppModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.noraScale) private var scale

    var body: some View {
        let rows = TileCatalog.scanRows
        VStack(alignment: .leading, spacing: 8 * scale) {
            SectionLabel("Choose what to do")
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex == rows.count - 1 {
                    SectionLabel("Text size in the app you’re using")
                        .padding(.top, 2 * scale)
                }
                HStack(spacing: 12 * scale) {
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

    var body: some View {
        let enabled = model.interaction.acceptsInput
        TileFace(tile: tile, compact: compact, enabled: enabled,
                 scanHighlighted: model.scanner.isHighlighted(tile),
                 dwellStart: model.dwellTarget == tile.id ? model.dwellStartedAt : nil,
                 dwellSeconds: model.settings.dwellSeconds)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { model.activate(tile) } }
            .onHover { model.hover(tile, inside: $0) }
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
    let scanHighlighted: Bool
    let dwellStart: Date?
    let dwellSeconds: Double
    @Environment(\.isFocused) private var isFocused
    @Environment(\.noraScale) private var scale
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let radius = 22 * scale
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if compact {
                HStack(spacing: 12 * scale) {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 26 * scale, weight: .semibold))
                    Text(tile.title)
                        .font(.nora(22, .bold, scale: scale))
                        .lineLimit(1)
                }
            } else {
                VStack(spacing: 6 * scale) {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 40 * scale, weight: .semibold))
                        .frame(height: 46 * scale)
                    Text(tile.title)
                        .font(.nora(25, .bold, scale: scale))
                        .lineLimit(1)
                    Text(tile.detail)
                        .font(.nora(15, .semibold, scale: scale))
                        .lineLimit(2)
                }
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(10 * scale)
        .frame(maxWidth: .infinity, minHeight: (compact ? 60 : 180) * scale)
        .background(shape.fill(Color(hex: tile.color)))
        .overlay(shape.strokeBorder(Color.white.opacity(contrast == .increased ? 1 : 0.22), lineWidth: (contrast == .increased ? 3 : 1) * scale))
        .overlay(alignment: .topLeading) {
            Text(tile.shortcut)
                .font(.system(size: 13 * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 7 * scale)
                .padding(.vertical, 3 * scale)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .padding(8 * scale)
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
                Circle().stroke(Color.white.opacity(0.35), lineWidth: 8 * scale)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 8 * scale, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 60 * scale, height: 60 * scale)
            .padding(8 * scale)
            .background(Circle().fill(Color.black.opacity(0.4)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
