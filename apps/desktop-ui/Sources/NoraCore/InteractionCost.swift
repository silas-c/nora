import Foundation

/// Keystroke-Level Model operators (Card, Moran & Newell, 1983).
public enum KLMOperator: Sendable, Equatable {
    case keystrokes(Int)
    case point
    case buttonPress
    case home
    case mental

    public var seconds: Double {
        switch self {
        case .keystrokes(let count): Double(count) * KLM.keystroke
        case .point: KLM.point
        case .buttonPress: KLM.button
        case .home: KLM.home
        case .mental: KLM.mental
        }
    }
}

public enum KLM {
    /// Average non-secretarial typist (about 40 words per minute).
    public static let keystroke = 0.28
    public static let point = 1.1
    /// One press or one release; a click is two.
    public static let button = 0.1
    public static let home = 0.4
    public static let mental = 1.35

    public static func seconds(_ operators: [KLMOperator]) -> Double {
        operators.reduce(0) { $0 + $1.seconds }
    }

    public static let click: [KLMOperator] = [.mental, .point, .buttonPress, .buttonPress]
}

public struct ManualBaseline: Sendable, Equatable {
    public var steps: [String]
    public var clicks: Int
    public var keystrokes: Int
    public var operators: [KLMOperator]
    /// Set when Nora saves no physical effort, so the demo never overstates a benefit.
    public var note: String?

    public var seconds: Double { KLM.seconds(operators) }
    public var actions: Int { clicks + keystrokes }
}

public enum InteractionCost {
    public static let tileOperators = KLM.click

    public static func typedOperators(characters: Int) -> [KLMOperator] {
        [.mental, .home, .keystrokes(characters + 1)]
    }

    /// Conventional mouse-and-keyboard route to the same result, starting with the hand on the mouse.
    public static func baseline(for intent: String) -> ManualBaseline? {
        switch intent {
        case "OPEN_SCHOOL", "OPEN_CANVAS":
            return canvas
        case "OPEN_COURSES":
            return ManualBaseline(steps: canvas.steps + ["Move back to the mouse", "Click Courses in Canvas"],
                                  clicks: 3, keystrokes: 18, operators: canvas.operators + [.home] + KLM.click)
        case "OPEN_DOG_PHOTOS":
            return ManualBaseline(steps: ["Click Microsoft Edge in the Dock", "Click the address bar", "Type dogs",
                                          "Press Return", "Move back to the mouse", "Click Images"],
                                  clicks: 3, keystrokes: 5,
                                  operators: KLM.click + KLM.click + [.home, .keystrokes(4), .keystrokes(1), .home] + KLM.click)
        case "OPEN_PHOTOS", "OPEN_INTERNET", "OPEN_EDGE", "OPEN_FINDER":
            return ManualBaseline(steps: ["Find the app in the Dock", "Click it"], clicks: 1, keystrokes: 0,
                                  operators: KLM.click, note: "About the same effort as the Dock; Nora helps by naming the goal instead of the app.")
        case "ZOOM_IN":
            return ManualBaseline(steps: ["Hold Command", "Press ="], clicks: 0, keystrokes: 2,
                                  operators: [.mental, .home, .keystrokes(2)],
                                  note: "Replaces a two-key shortcut with one press, which matters when pressing two keys at once is hard.")
        case "ZOOM_OUT":
            return ManualBaseline(steps: ["Hold Command", "Press -"], clicks: 0, keystrokes: 2,
                                  operators: [.mental, .home, .keystrokes(2)],
                                  note: "Replaces a two-key shortcut with one press, which matters when pressing two keys at once is hard.")
        default:
            return nil
        }
    }

    private static let canvas = ManualBaseline(
        steps: ["Click Microsoft Edge in the Dock", "Click the address bar", "Type canvas.temple.edu", "Press Return"],
        clicks: 2, keystrokes: 18,
        operators: KLM.click + KLM.click + [.home, .keystrokes(17), .keystrokes(1)])
}

/// Accounting-only estimate of which task a typed request was. Routing always belongs to the agent.
public enum IntentEstimator {
    public static func intent(for input: UserInput) -> String? {
        switch input {
        case .aac(let intent): return intent
        case .text(let text), .voice(let text): return intent(forText: text)
        }
    }

    public static func intent(forText text: String) -> String? {
        let request = AliasResolver.normalize(text)
        let routes: [(String, String)] = [
            (#"^open canvas and go to (?:my )?courses$"#, "OPEN_COURSES"),
            (#"^open (?:canvas|(?:my )?school(?:work| thing)?)(?: (?:in|on) (?:microsoft )?edge)?$"#, "OPEN_SCHOOL"),
            (#"^(?:show(?: me)?|open|find) dog (?:photos|pictures)(?: on google)?$"#, "OPEN_DOG_PHOTOS"),
            (#"^open photos$"#, "OPEN_PHOTOS"),
            (#"^open (?:microsoft )?edge$"#, "OPEN_INTERNET"),
            (#"^open finder$"#, "OPEN_FINDER"),
            (#"^(?:zoom in|make (?:the )?text bigger)$"#, "ZOOM_IN"),
            (#"^(?:zoom out|make (?:the )?text smaller)$"#, "ZOOM_OUT"),
        ]
        return routes.first { request.range(of: $0.0, options: .regularExpression) != nil }?.1
    }
}

public struct TallyEntry: Sendable, Equatable {
    public var intent: String
    public var noraActions: Int
    public var noraSeconds: Double
    public var manual: ManualBaseline
    public var agentSeconds: Double
}

/// Running comparison of Nora against the conventional route, for successful tasks with a known baseline.
public struct SessionTally: Sendable, Equatable {
    public private(set) var tasks = 0
    public private(set) var noraActions = 0
    public private(set) var manualActions = 0
    public private(set) var noraSeconds = 0.0
    public private(set) var manualSeconds = 0.0
    public private(set) var last: TallyEntry?

    public init() {}

    public var actionsSaved: Int { manualActions - noraActions }
    public var secondsSaved: Double { manualSeconds - noraSeconds }

    public mutating func record(intent: String, noraOperators: [KLMOperator], noraActions: Int, agentSeconds: Double) {
        guard let manual = InteractionCost.baseline(for: intent) else { return }
        let noraSeconds = KLM.seconds(noraOperators)
        tasks += 1
        self.noraActions += noraActions
        manualActions += manual.actions
        self.noraSeconds += noraSeconds
        manualSeconds += manual.seconds
        last = TallyEntry(intent: intent, noraActions: noraActions, noraSeconds: noraSeconds, manual: manual, agentSeconds: agentSeconds)
    }

    public mutating func reset() {
        self = SessionTally()
    }
}
