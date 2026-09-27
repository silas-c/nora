import Foundation
import Testing
@testable import NoraCore

@Suite("Double tap")
struct DoubleTapTests {
    /// Taps Command at each (press, release) time and returns which releases completed a double tap.
    private func taps(_ times: [(TimeInterval, TimeInterval)], into detector: inout DoubleTap) -> [Bool] {
        times.map { press, release in
            _ = detector.modifiersChanged(key: true, others: false, at: press)
            return detector.modifiersChanged(key: false, others: false, at: release)
        }
    }

    @Test func twoQuickTapsFireOnTheSecondRelease() {
        var detector = DoubleTap()
        #expect(taps([(0, 0.1), (0.3, 0.4)], into: &detector) == [false, true])
    }

    @Test func aThirdTapStartsOver() {
        var detector = DoubleTap()
        #expect(taps([(0, 0.1), (0.3, 0.4), (0.6, 0.7), (0.9, 1.0)], into: &detector) == [false, true, false, true])
    }

    @Test func slowTapsAndHoldsDoNotCount() {
        var slow = DoubleTap()
        #expect(taps([(0, 0.1), (0.6, 0.7)], into: &slow) == [false, false])
        var held = DoubleTap()
        #expect(taps([(0, 0.5), (0.6, 0.7)], into: &held) == [false, false])
    }

    @Test func aKeyPressedBetweenTapsCancels() {
        var detector = DoubleTap()
        _ = taps([(0, 0.1)], into: &detector)
        _ = detector.modifiersChanged(key: true, others: false, at: 0.2)
        detector.interrupt()
        #expect(detector.modifiersChanged(key: false, others: false, at: 0.3) == false)
        #expect(taps([(0.4, 0.5)], into: &detector) == [false])
    }

    @Test func anotherModifierCancels() {
        var detector = DoubleTap()
        _ = taps([(0, 0.1)], into: &detector)
        _ = detector.modifiersChanged(key: true, others: false, at: 0.2)
        _ = detector.modifiersChanged(key: true, others: true, at: 0.25)
        _ = detector.modifiersChanged(key: true, others: false, at: 0.3)
        #expect(detector.modifiersChanged(key: false, others: false, at: 0.35) == false)
    }
}
