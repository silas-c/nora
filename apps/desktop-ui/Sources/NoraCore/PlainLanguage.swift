import Foundation

public enum FailureKind: Sendable, Equatable {
    case notUnderstood
    case actionFailed
    case expired
    case connection
}

public enum Recovery: Sendable, Equatable {
    case askAgain
    case openAccessibilitySettings
    case restartAgent
}

public struct FailureInfo: Sendable, Equatable {
    public var kind: FailureKind
    /// Plain-language explanation shown in large type.
    public var message: String
    /// The agent's original wording, kept for the transparency panel.
    public var detail: String
    public var suggestions: [Suggestion]
    public var recovery: Recovery?

    public init(kind: FailureKind, message: String, detail: String, suggestions: [Suggestion] = [], recovery: Recovery? = nil) {
        self.kind = kind
        self.message = message
        self.detail = detail
        self.suggestions = suggestions
        self.recovery = recovery
    }
}

/// Rewrites agent and helper errors so they say what happened and what to do next.
public enum PlainLanguage {
    public static func failure(for raw: String, input: UserInput?) -> FailureInfo {
        let lower = raw.lowercased()
        if raw.hasPrefix("Try “") || raw.hasPrefix("Try \"") {
            let heard = input?.utterance?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = heard.isEmpty
                ? "I’m not sure what that means yet."
                : "I’m not sure what “\(heard)” means yet."
            return FailureInfo(kind: .notUnderstood, message: message, detail: raw, suggestions: Repair.suggestions(for: heard))
        }
        if let app = capture(raw, pattern: #"Unable to find application named '(.+?)'"#) {
            return FailureInfo(kind: .actionFailed, message: "\(app) isn’t installed on this Mac.", detail: raw)
        }
        if lower.contains("accessibility permission") || lower.contains("privacy & security") {
            return FailureInfo(kind: .actionFailed, message: "Nora needs Accessibility permission to do that.",
                               detail: raw, recovery: .openAccessibilitySettings)
        }
        if lower.contains("already running") {
            return FailureInfo(kind: .actionFailed, message: "Nora is still finishing the last request. Please wait a moment.", detail: raw)
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return FailureInfo(kind: .actionFailed, message: "The computer didn’t answer in time. Nothing else was tried.",
                               detail: raw, recovery: .askAgain)
        }
        if lower.contains("expired") {
            return FailureInfo(kind: .expired, message: "That choice timed out for your safety, so nothing was done.",
                               detail: raw, recovery: .askAgain)
        }
        if lower.contains("changed") && lower.contains("no action was executed") {
            return FailureInfo(kind: .actionFailed, message: "Something on screen changed, so Nora stopped. Nothing was done.",
                               detail: raw, recovery: .askAgain)
        }
        return FailureInfo(kind: .actionFailed, message: raw, detail: raw)
    }

    private static func capture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// Human-readable descriptions of the exact action a confirmation would run.
public enum ActionDescriber {
    public static func describe(_ action: ComputerAction) -> String {
        switch action.type {
        case "open_url":
            let destination = action.url ?? "a web page"
            return action.browser.map { "Open \(destination) in \($0)" } ?? "Open \(destination)"
        case "launch_app":
            return "Open the app “\(action.app ?? "unknown")”"
        case "focus_app":
            return "Switch to \(action.app ?? "an app")"
        case "click":
            return "Press the on-screen control \(action.target ?? "")".trimmingCharacters(in: .whitespaces)
        case "type_text":
            let text = "Type “\(action.text ?? "")”"
            return action.target.map { "\(text) into control \($0)" } ?? text
        case "keypress":
            let keys = (action.modifiers ?? []).map(keyName) + [keyName(action.key ?? "")]
            return "Press " + keys.joined(separator: " + ")
        case "scroll":
            return "Scroll \(action.direction ?? "") \(action.amount ?? 3) lines"
        default:
            return "Run the action “\(action.type)”"
        }
    }

    /// The agent formats prompts as "<acting message> Action: <json>"; the first part is the human summary.
    public static func headline(_ confirmation: ConfirmationRequest) -> String {
        let summary = confirmation.message.components(separatedBy: " Action: ").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return summary.isEmpty ? describe(confirmation.action) : summary
    }

    public static func riskTitle(_ risk: RiskLevel) -> String {
        switch risk {
        case .destructive: "This can’t be undone"
        case .sensitive: "This changes something"
        case .safe: "This only opens or shows something"
        }
    }

    public static func riskExplanation(_ risk: RiskLevel) -> String {
        switch risk {
        case .destructive: "It could permanently remove or change your things."
        case .sensitive: "It could send, submit, or change information."
        case .safe: "Nothing will be removed or sent."
        }
    }

    private static func keyName(_ key: String) -> String {
        switch key.uppercased() {
        case "CMD", "COMMAND": "Command"
        case "SHIFT": "Shift"
        case "ALT", "OPTION": "Option"
        case "CTRL", "CONTROL": "Control"
        case "+": "Plus"
        case "-": "Minus"
        case "=": "Equals"
        default: key.capitalized
        }
    }
}
