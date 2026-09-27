import AppKit
import ApplicationServices

struct ElementSnapshot: Encodable {
    let id: String
    let role: String
    let label: String?
    let enabled: Bool
    let actions: [String]
}

struct ComputerSnapshot {
    let snapshotGeneration: String
    let activeApp: String
    let activeWindow: String?
    let elements: [ElementSnapshot]
    let truncated: Bool
}

enum SnapshotError: LocalizedError {
    case permissionDenied
    case noWindow
    case webContentUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission is required. Enable it for the app running mac-helper in System Settings > Privacy & Security > Accessibility."
        case .noWindow:
            return "The active app has no accessible window. Focus a window and try again."
        case .webContentUnavailable:
            return "Edge did not expose webpage controls. Reload the page or enable accessibility in edge://accessibility and try again."
        }
    }
}

struct ControlError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class SnapshotReader {
    private(set) var elementsByID: [String: AXUIElement] = [:]
    private var enhancedApp: AXUIElement?
    private var enhancedPID: pid_t?
    private var snapshotPID: pid_t?
    private var snapshotWindowTitle: String?
    private var snapshotGeneration: String?
    private var nextElementID = 1

    func read(_ app: NSRunningApplication) throws -> ComputerSnapshot {
        elementsByID.removeAll()
        snapshotPID = nil
        snapshotWindowTitle = nil
        snapshotGeneration = nil
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else { throw SnapshotError.permissionDenied }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let isEdge = app.bundleIdentifier == "com.microsoft.edgemac"
        if isEdge && enhancedPID != app.processIdentifier {
            stop()
            // Chromium exposes webpage nodes only after an accessibility client requests them.
            _ = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            enhancedApp = appElement
            enhancedPID = app.processIdentifier
        }

        let deadline = Date().addingTimeInterval(isEdge ? 3 : 0)
        while true {
            let (snapshot, hasWebArea) = try readOnce(app, appElement)
            if !isEdge || hasWebArea {
                let generation = UUID().uuidString
                snapshotPID = app.processIdentifier
                snapshotWindowTitle = snapshot.activeWindow
                snapshotGeneration = generation
                return ComputerSnapshot(snapshotGeneration: generation, activeApp: snapshot.activeApp,
                                        activeWindow: snapshot.activeWindow, elements: snapshot.elements,
                                        truncated: snapshot.truncated)
            }
            if Date() >= deadline {
                elementsByID.removeAll()
                throw SnapshotError.webContentUnavailable
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    func stop() {
        if let enhancedApp {
            _ = AXUIElementSetAttributeValue(enhancedApp, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        enhancedApp = nil
        enhancedPID = nil
    }

    func click(_ id: String, generation: String, expected: ExpectedTarget? = nil) throws {
        let element = try target(id, generation: generation, expected: expected)
        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        if ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role),
           AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
            consumeSnapshot()
            return
        }
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              (names as? [String])?.contains("AXPress") == true else {
            throw ControlError(message: "Target \(id) does not support clicking")
        }
        consumeSnapshot()
        // Chromium currently reports AXPress success for webpage nodes without
        // dispatching their DOM activation. Use the already validated element's
        // accessibility bounds for one physical click instead.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.microsoft.edgemac" {
            try clickElementAtCenter(element)
            return
        }
        let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard status == .success else {
            throw ControlError(message: "Could not click \(id) (Accessibility error \(status.rawValue))")
        }
    }

    func setText(_ text: String, in id: String, generation: String, expected: ExpectedTarget? = nil) throws {
        let element = try target(id, generation: generation, expected: expected)
        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        guard ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role) else {
            throw ControlError(message: "Target \(id) is not a text input")
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            throw ControlError(message: "Target \(id) does not allow setting text")
        }
        consumeSnapshot()
        let status = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString)
        guard status == .success else {
            throw ControlError(message: "Could not set text in \(id) (Accessibility error \(status.rawValue))")
        }
    }

    private func consumeSnapshot() {
        elementsByID.removeAll()
        snapshotPID = nil
        snapshotWindowTitle = nil
        snapshotGeneration = nil
    }

    private func target(_ id: String, generation: String, expected: ExpectedTarget?) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw SnapshotError.permissionDenied }
        guard let app = NSWorkspace.shared.frontmostApplication,
              generation == snapshotGeneration,
              app.processIdentifier == snapshotPID,
              let element = elementsByID[id] else {
            throw ControlError(message: "Target \(id) is stale. Take a new snapshot and try again.")
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = attribute(appElement, kAXFocusedWindowAttribute)
                ?? attribute(appElement, kAXMainWindowAttribute) else {
            throw ControlError(message: "Target \(id) is stale. Take a new snapshot and try again.")
        }
        let currentTitle: String? = attribute(window, kAXTitleAttribute)
        guard currentTitle == snapshotWindowTitle else {
            throw ControlError(message: "Target \(id) is stale. Take a new snapshot and try again.")
        }
        let enabled: Bool = attribute(element, kAXEnabledAttribute) ?? true
        guard enabled else { throw ControlError(message: "Target \(id) is disabled") }
        if let expected {
            let role: String = attribute(element, kAXRoleAttribute) ?? "unknown"
            var names: CFArray?
            let status = AXUIElementCopyActionNames(element, &names)
            let actions = status == .success ? (names as? [String] ?? []) : []
            let title: String? = attribute(element, kAXTitleAttribute)
            let description: String? = attribute(element, kAXDescriptionAttribute)
            let linkValue: String? = role == "AXLink" ? attribute(element, kAXValueAttribute) : nil
            let label = [title, description, linkValue].compactMap { $0 }.first { !$0.isEmpty }
            guard app.localizedName == expected.app,
                  currentTitle == expected.window,
                  role == expected.role,
                  label == expected.label,
                  Set(actions) == Set(expected.actions) else {
                throw ControlError(message: "Target \(id) changed after it was selected. Take a new snapshot and try again.")
            }
        }
        return element
    }

    private func readOnce(_ app: NSRunningApplication, _ appElement: AXUIElement) throws -> (ComputerSnapshot, Bool) {
        elementsByID.removeAll()
        guard let window: AXUIElement = attribute(appElement, kAXFocusedWindowAttribute)
                ?? attribute(appElement, kAXMainWindowAttribute) else {
            throw SnapshotError.noWindow
        }

        let title: String? = attribute(window, kAXTitleAttribute)
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var index = 0
        var elements: [ElementSnapshot] = []
        var hasWebArea = false
        var truncated = false
        let maxNodes = 3_000
        let maxDepth = 80
        let inputRoles: Set<String> = [
            "AXButton", "AXCheckBox", "AXComboBox", "AXLink", "AXMenuItem",
            "AXPopUpButton", "AXRadioButton", "AXSearchField", "AXSlider",
            "AXTab", "AXTextArea", "AXTextField"
        ]

        while index < queue.count && index < maxNodes {
            let (element, depth) = queue[index]
            index += 1

            var names: CFArray?
            let status = AXUIElementCopyActionNames(element, &names)
            let actions = status == .success ? (names as? [String] ?? []) : []
            let role: String = attribute(element, kAXRoleAttribute) ?? "unknown"
            if role == "AXWebArea" { hasWebArea = true }
            if actions.contains("AXPress") || inputRoles.contains(role) {
                let title: String? = attribute(element, kAXTitleAttribute)
                let description: String? = attribute(element, kAXDescriptionAttribute)
                let linkValue: String? = role == "AXLink" ? attribute(element, kAXValueAttribute) : nil
                let label = [title, description, linkValue].compactMap { $0 }.first { !$0.isEmpty }
                let enabled: Bool = attribute(element, kAXEnabledAttribute) ?? true
                let id = "e\(nextElementID)"
                nextElementID += 1
                elementsByID[id] = element
                elements.append(ElementSnapshot(id: id, role: role, label: label, enabled: enabled, actions: actions))
            }

            if let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) {
                if depth < maxDepth {
                    queue.append(contentsOf: children.map { ($0, depth + 1) })
                } else if !children.isEmpty {
                    truncated = true
                }
            }
        }

        return (ComputerSnapshot(
            snapshotGeneration: "pending",
            activeApp: app.localizedName ?? "Unknown",
            activeWindow: title,
            elements: elements,
            truncated: truncated || index < queue.count
        ), hasWebArea)
    }
}

private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value as? T
}
