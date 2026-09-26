import Carbon
import Foundation

/// A system-wide shortcut through Carbon, which needs no Accessibility or Input Monitoring permission.
@MainActor
final class HotKey {
    private static var action: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKey.action?() }
            return noErr
        }, 1, &eventType, nil, &handler)
        guard installed == noErr else { return nil }
        let identifier = EventHotKeyID(signature: OSType(0x4E4F5241), id: 1)
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), identifier, GetApplicationEventTarget(), 0, &reference) == noErr else {
            return nil
        }
    }
}
