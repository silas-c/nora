import AppKit
import NoraCore

/// `Nora --self-test <folder>` drives the running app through the demo flows against its real agent process,
/// saving an image of the live panel after each step and a JSON report. Needs no extra permissions.
@MainActor
enum SelfTest {
    struct Step: Encodable {
        var name: String
        var title: String
        var message: String
        var image: String
    }

    private struct Report: Encodable {
        var passed: Bool
        var failures: [String]
        var frontmostAppWhileNoraHasKeyboard: String
        var steps: [Step]
        var agentActions: [String]
        var effort: String
        var evaluationCSV: String
    }

    static func run(model: AppModel, panel: NSPanel, directory: URL, quitWhenDone: Bool) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.speaker.muted = true
        defer { model.speaker.muted = false }
        var steps: [Step] = []
        var failures: [String] = []

        func capture(_ name: String) {
            let status = StatusPresentation(model: model)
            let file = "\(String(format: "%02d", steps.count + 1))-\(name).png"
            if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(file))
            }
            steps.append(Step(name: name, title: status.title, message: status.message, image: file))
        }

        func wait(_ label: String, until condition: () -> Bool) async {
            for _ in 0..<200 where !condition() {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if !condition() { failures.append("Timed out waiting for \(label)") }
            try? await Task.sleep(for: .milliseconds(250))
        }

        /// Runs one step and waits until it produces its own evaluation record.
        func step(_ name: String, _ trigger: () -> Void) async {
            let before = model.evaluation.records.count
            trigger()
            await wait(name) { model.evaluation.records.count > before && !model.interaction.isBusy }
            capture(name)
        }

        func expectLast(modality: String, request: String) {
            guard let last = model.evaluation.records.last, last.modality == modality, last.request == request else {
                let actual = model.evaluation.records.last.map { "\($0.modality) “\($0.request)”" } ?? "nothing"
                failures.append("Expected \(modality) “\(request)”, got \(actual)")
                return
            }
        }

        await wait("the agent to connect") { model.interaction.phase == .idle }
        capture("ready")

        await step("school-tile") { model.activate(TileCatalog.home[0]) }
        expectLast(modality: "tile", request: "School")

        await step("typed-open-canvas") {
            model.draft = "Open Canvas"
            model.submitDraft()
        }
        expectLast(modality: "text", request: "Open Canvas")

        await step("repair-choices") {
            model.draft = "open my canvs"
            model.submitDraft()
        }
        if case .failed(let failure) = model.interaction.phase, let first = failure.suggestions.first {
            await step("repair-chosen") { model.choose(first) }
            if model.evaluation.records.last?.reformulations != 1 { failures.append("The repair was not counted as one reformulation") }
        } else {
            failures.append("No repair choices were offered")
        }

        await step("courses-tile") { model.activate(TileCatalog.home[1]) }
        expectLast(modality: "tile", request: "Courses")

        model.submitExample("Delete everything in Downloads")
        await wait("the confirmation prompt") { model.interaction.pendingConfirmation != nil }
        capture("confirmation")
        await step("cancelled") { model.decide(approved: false) }
        if model.interaction.phase != .done("Nothing was changed.", cancelled: true) { failures.append("Cancel did not report that nothing changed") }

        model.submitExample("Delete everything in Downloads")
        await wait("the second confirmation prompt") { model.interaction.pendingConfirmation != nil }
        await step("approved") { model.decide(approved: true) }

        // Keyboard access (issue #3): real key events through the app's own event queue.
        panel.makeKeyAndOrderFront(nil)
        model.requestedFocus = .tile(TileCatalog.home[0].id)
        try? await Task.sleep(for: .milliseconds(400))
        // The helper posts shortcuts to the frontmost app's process, not to whichever app is merely active.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if !panel.isKeyWindow { failures.append("The panel did not take keyboard focus") }
        if frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            failures.append("Nora is the frontmost app, so a zoom shortcut would reach Nora instead of the app in use")
        }
        press(String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!), keyCode: 124, in: panel)
        try? await Task.sleep(for: .milliseconds(300))
        if model.currentFocus != .tile("OPEN_COURSES") {
            failures.append("Right arrow did not move focus to Courses (focus: \(String(describing: model.currentFocus)))")
        }
        await step("keyboard-arrow-return") { press("\r", keyCode: 36, in: panel) }
        expectLast(modality: "keyboard", request: "Courses")

        await step("keyboard-shortcut") { press("3", keyCode: 20, in: panel) }
        expectLast(modality: "keyboard shortcut", request: "Internet")

        press("/", keyCode: 44, in: panel)
        try? await Task.sleep(for: .milliseconds(300))
        for character in "zoom in" { press(String(character), keyCode: 0, in: panel) }
        try? await Task.sleep(for: .milliseconds(200))
        await step("keyboard-typed") { press("\r", keyCode: 36, in: panel) }
        expectLast(modality: "text", request: "zoom in")

        model.submitExample("Delete everything in Downloads")
        await wait("the keyboard confirmation prompt") { model.interaction.pendingConfirmation != nil }
        await step("keyboard-escape-cancels") { press("\u{1b}", keyCode: 53, in: panel) }
        if model.interaction.phase != .done("Nothing was changed.", cancelled: true) { failures.append("Escape did not cancel the confirmation") }

        model.refreshHistory()
        try? await Task.sleep(for: .milliseconds(400))
        let executed = model.history.filter { $0.action.app == "Mock deletion executor" }.count
        if executed != 1 { failures.append("Expected exactly one approved practice deletion, the agent recorded \(executed)") }

        let report = Report(
            passed: failures.isEmpty,
            failures: failures,
            frontmostAppWhileNoraHasKeyboard: frontmost?.localizedName ?? "unknown",
            steps: steps,
            agentActions: model.history.map { "\($0.success ? "✓" : "✗") \(ActionDescriber.describe($0.action))" },
            effort: "\(model.tally.noraActions) presses in Nora vs about \(model.tally.manualActions) the usual way. \(CostBar.timeSummary(model.tally.secondsSaved))",
            evaluationCSV: model.evaluation.csv())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(report) {
            try? data.write(to: directory.appendingPathComponent("report.json"))
        }
        if quitWhenDone { NSApp.terminate(nil) }
    }

    private static func press(_ characters: String, keyCode: UInt16, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }
}
