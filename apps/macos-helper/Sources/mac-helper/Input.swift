import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

func typeFocusedText(_ text: String) throws {
    guard AXIsProcessTrusted() else { throw SnapshotError.permissionDenied }
    guard let app = NSWorkspace.shared.frontmostApplication else {
        throw ControlError(message: "Could not determine the active app")
    }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
        throw ControlError(message: "No focused text input")
    }
    let focused = value as! AXUIElement
    var roleValue: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleValue)
    guard let role = roleValue as? String,
          ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role) else {
        throw ControlError(message: "Focused control is not a text input")
    }
    var enabledValue: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(focused, kAXEnabledAttribute as CFString, &enabledValue)
    if let enabled = enabledValue as? Bool, !enabled {
        throw ControlError(message: "Focused text input is disabled")
    }

    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable) == .success,
          settable.boolValue else {
        throw ControlError(message: "Focused text input does not allow setting text")
    }
    let status = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, text as CFString)
    guard status == .success else {
        throw ControlError(message: "Could not set focused text (Accessibility error \(status.rawValue))")
    }
}

/// Presses a key for each character, as a keyboard does. A newline presses Return.
func typeKeystrokes(_ text: String, selectingAll: Bool, to pid: pid_t) throws {
    guard CGPreflightPostEventAccess() else {
        throw ControlError(message: "Keyboard event permission is required in System Settings > Privacy & Security > Accessibility")
    }
    func post(_ code: CGKeyCode, flags: CGEventFlags = [], text: String? = nil) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            throw ControlError(message: "Could not create keyboard event")
        }
        for event in [down, up] {
            event.flags = flags
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event.postToPid(pid)
        }
        usleep(8_000)
    }
    if selectingAll {
        try post(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        usleep(50_000)
    }
    for character in text {
        if character == "\n" {
            usleep(150_000)
            try post(CGKeyCode(kVK_Return))
        } else {
            try post(0, text: String(character))
        }
    }
}

func pressKey(_ key: String, modifiers: [String]) throws {
    guard AXIsProcessTrusted() else { throw SnapshotError.permissionDenied }
    guard CGPreflightPostEventAccess() else {
        throw ControlError(message: "Keyboard event permission is required in System Settings > Privacy & Security > Accessibility")
    }
    guard let app = NSWorkspace.shared.frontmostApplication else {
        throw ControlError(message: "Could not determine the active app")
    }

    var flags: CGEventFlags = []
    for modifier in modifiers {
        switch modifier.uppercased() {
        case "CMD", "COMMAND": flags.insert(.maskCommand)
        case "SHIFT": flags.insert(.maskShift)
        case "ALT", "OPTION": flags.insert(.maskAlternate)
        case "CTRL", "CONTROL": flags.insert(.maskControl)
        default: throw ControlError(message: "Unsupported modifier: \(modifier)")
        }
    }

    let code: CGKeyCode
    switch key.uppercased() {
    case "ENTER", "RETURN": code = CGKeyCode(kVK_Return)
    case "TAB": code = CGKeyCode(kVK_Tab)
    case "SPACE": code = CGKeyCode(kVK_Space)
    case "BACKSPACE", "DELETE": code = CGKeyCode(kVK_Delete)
    case "ESC", "ESCAPE": code = CGKeyCode(kVK_Escape)
    case "LEFT": code = CGKeyCode(kVK_LeftArrow)
    case "RIGHT": code = CGKeyCode(kVK_RightArrow)
    case "UP": code = CGKeyCode(kVK_UpArrow)
    case "DOWN": code = CGKeyCode(kVK_DownArrow)
    case "+":
        code = CGKeyCode(kVK_ANSI_Equal)
        flags.insert(.maskShift)
    case "=": code = CGKeyCode(kVK_ANSI_Equal)
    case "-": code = CGKeyCode(kVK_ANSI_Minus)
    case "A": code = CGKeyCode(kVK_ANSI_A)
    case "C": code = CGKeyCode(kVK_ANSI_C)
    case "L": code = CGKeyCode(kVK_ANSI_L)
    case "V": code = CGKeyCode(kVK_ANSI_V)
    case "R": code = CGKeyCode(kVK_ANSI_R)
    case "T": code = CGKeyCode(kVK_ANSI_T)
    case "W": code = CGKeyCode(kVK_ANSI_W)
    default: throw ControlError(message: "Unsupported key: \(key)")
    }

    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
        throw ControlError(message: "Could not create keyboard event")
    }
    down.flags = flags
    up.flags = flags
    down.postToPid(app.processIdentifier)
    up.postToPid(app.processIdentifier)
}

func scroll(_ direction: String, amount: Int) throws {
    guard AXIsProcessTrusted() else { throw SnapshotError.permissionDenied }
    guard CGPreflightPostEventAccess() else {
        throw ControlError(message: "Scroll event permission is required in System Settings > Privacy & Security > Accessibility")
    }
    guard let app = NSWorkspace.shared.frontmostApplication else {
        throw ControlError(message: "Could not determine the active app")
    }
    guard amount > 0 else { throw ControlError(message: "Scroll amount must be positive") }
    let lines = Int32(min(amount, 20))
    let vertical: Int32
    let horizontal: Int32
    switch direction.lowercased() {
    case "up": vertical = lines; horizontal = 0
    case "down": vertical = -lines; horizontal = 0
    case "left": vertical = 0; horizontal = lines
    case "right": vertical = 0; horizontal = -lines
    default: throw ControlError(message: "Unsupported scroll direction: \(direction)")
    }
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                              wheel1: vertical, wheel2: horizontal, wheel3: 0) else {
        throw ControlError(message: "Could not create scroll event")
    }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard let window = frontWindow(of: appElement) else { throw SnapshotError.noWindow }
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let positionValue, let sizeValue,
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        throw ControlError(message: "Could not locate the active window for scrolling")
    }
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
        throw ControlError(message: "Could not locate the active window for scrolling")
    }
    event.location = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    event.post(tap: .cgSessionEventTap)
}
