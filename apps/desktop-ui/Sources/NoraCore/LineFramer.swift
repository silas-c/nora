import Foundation

/// Splits a byte stream into newline-terminated lines, the framing used by the agent transport.
public struct LineFramer: Sendable {
    public static let maximumLineLength = 1 << 20

    private var buffer = Data()
    public private(set) var overflowed = false

    public init() {}

    public mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[buffer.startIndex..<newline])
            if line.last == 0x0D { line.removeLast() }
            lines.append(line)
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if buffer.count > Self.maximumLineLength {
            buffer.removeAll()
            overflowed = true
        }
        return lines
    }
}
