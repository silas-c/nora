import AppKit
import NoraCore

/// Double-tapping Command on its own calls the action, from any app.
/// macOS shares modifier changes with every app but hides other keys without Accessibility permission, so a key
/// or click in between is found through the system's idle timers instead. That keeps Command-C then Command-V from counting.
@MainActor
final class CommandDoubleTap {
    private static let otherInput: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    private var detector = DoubleTap()
    private var lastChangeAt: TimeInterval = 0
    private var monitors: [Any] = []

    init(action: @escaping () -> Void) {
        let handle = { [weak self] (event: NSEvent) in
            if self?.observe(event) == true { action() }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handle) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            handle(event)
            return event
        }) { monitors.append(monitor) }
    }

    private func observe(_ event: NSEvent) -> Bool {
        let idle = Self.otherInput.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
        if ProcessInfo.processInfo.systemUptime - idle > lastChangeAt { detector.interrupt() }
        lastChangeAt = event.timestamp
        let flags = event.modifierFlags
        return detector.modifiersChanged(key: flags.contains(.command),
                                         others: !flags.isDisjoint(with: [.shift, .control, .option]),
                                         at: event.timestamp)
    }
}
