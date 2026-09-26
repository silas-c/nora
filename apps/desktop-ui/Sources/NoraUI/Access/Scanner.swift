import NoraCore
import Observation

/// Single-switch row/column scanning. The highlight moves on its own; one press picks the row,
/// the next picks the tile. Every highlight is spoken, so scanning also works without looking.
@Observable @MainActor
final class Scanner {
    enum Level: Equatable {
        case rows
        case items(row: Int)
    }

    let rows = TileCatalog.scanRows
    private(set) var isRunning = false
    private(set) var level: Level = .rows
    private(set) var index = 0

    @ObservationIgnored var interval: () -> Double = { 1.4 }
    @ObservationIgnored var isPaused: () -> Bool = { false }
    @ObservationIgnored var onCue: (String) -> Void = { _ in }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cycles = 0

    static let rowNames = ["Top row", "Second row", "Text size"]

    func start() {
        isRunning = true
        level = .rows
        index = 0
        cycles = 0
        cue()
        schedule()
    }

    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
    }

    /// Handles one switch press. Returns the tile to activate when the press chose one.
    func press() -> TileSpec? {
        guard isRunning else {
            start()
            return nil
        }
        cycles = 0
        switch level {
        case .rows:
            level = .items(row: index)
            index = 0
            cue()
            schedule()
            return nil
        case .items(let row):
            let tile = rows[row][index]
            level = .rows
            index = 0
            schedule()
            return tile
        }
    }

    func isHighlighted(_ tile: TileSpec) -> Bool {
        guard isRunning, case .items(let row) = level, rows[row].indices.contains(index) else { return false }
        return rows[row][index] == tile
    }

    func isRowHighlighted(_ row: Int) -> Bool {
        isRunning && level == .rows && index == row
    }

    private func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.interval() ?? 1.4))
                guard !Task.isCancelled else { return }
                self?.advance()
            }
        }
    }

    private func advance() {
        guard !isPaused() else { return }
        switch level {
        case .rows:
            index += 1
            if index >= rows.count {
                index = 0
                cycles += 1
            }
        case .items(let row):
            index += 1
            if index >= rows[row].count {
                level = .rows
                index = row
                cycles += 1
            }
        }
        if cycles >= 3 {
            stop()
            onCue("Scanning paused. Press the switch to start again.")
            return
        }
        cue()
    }

    private func cue() {
        switch level {
        case .rows: onCue(Self.rowNames[index])
        case .items(let row): onCue(rows[row][index].title)
        }
    }
}
