import Foundation

/// Recognizes two quick taps of one modifier key, such as Command, pressed on its own.
/// Any other key, click, or modifier in between cancels it, so Command-C then Command-V never counts.
public struct DoubleTap: Sendable {
    /// Longer than this and the press is a hold, not a tap.
    public static let maximumHold: TimeInterval = 0.3
    /// The most time allowed between releasing the first tap and pressing the second.
    public static let maximumGap: TimeInterval = 0.4

    private var pressedAt: TimeInterval?
    private var firstTapReleasedAt: TimeInterval?
    private var idle = true

    public init() {}

    /// Call on every modifier change. Returns true when this release completes a double tap.
    public mutating func modifiersChanged(key: Bool, others: Bool, at time: TimeInterval) -> Bool {
        defer { idle = !key && !others }
        if others {
            interrupt()
            return false
        }
        if key {
            if idle { pressedAt = time }
            return false
        }
        guard let pressed = pressedAt else { return false }
        pressedAt = nil
        guard time - pressed <= Self.maximumHold else {
            firstTapReleasedAt = nil
            return false
        }
        if let first = firstTapReleasedAt, pressed - first <= Self.maximumGap {
            firstTapReleasedAt = nil
            return true
        }
        firstTapReleasedAt = time
        return false
    }

    /// Call when any other key or mouse button goes down.
    public mutating func interrupt() {
        pressedAt = nil
        firstTapReleasedAt = nil
    }
}
