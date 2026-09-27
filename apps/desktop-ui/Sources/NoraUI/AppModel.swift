import AppKit
import ApplicationServices
import NoraCore
import Observation

enum FocusTarget: Hashable {
    case tile(String)
    case textField
    case suggestion(String)
    case confirmCancel
    case confirmApprove
}

struct TraceEntry: Identifiable, Sendable {
    enum Direction: String, Sendable {
        case sent = "→"
        case received = "←"
        case diagnostic = "•"
        case note = "i"
    }

    let id: Int
    let time: Date
    let direction: Direction
    let requestId: String?
    let summary: String
    let raw: String
}

/// How the active request was made, for the effort tally and the evaluation log.
private struct RequestContext {
    var modality: String
    var label: String
    var intent: String?
    var noraActions: Int
    var noraOperators: [KLMOperator]
}

@Observable @MainActor
final class AppModel {
    static let maximumTextLength = 300

    private(set) var interaction = InteractionModel()
    private(set) var mode: AgentMode
    let settings: Settings
    let speaker: Speaker
    let voice: VoiceInput
    let scanner: Scanner

    var draft = "" {
        // Typing means the person chose the keyboard, so a recording started by summoning Nora stops.
        didSet { if !draft.isEmpty, voice.isListening { voice.cancel() } }
    }
    var requestedFocus: FocusTarget?
    var currentFocus: FocusTarget?
    private(set) var trace: [TraceEntry] = []
    private(set) var history: [HistoryEntry] = []
    private(set) var evaluation = EvaluationLog()
    private(set) var tally = SessionTally()
    private(set) var accessibilityTrusted: Bool
    private(set) var agentPID: Int32?
    private(set) var exportedEvaluation: URL?
    private(set) var permissionReport: PermissionReport?
    private(set) var dwellTarget: String?
    private(set) var dwellStartedAt: Date?

    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var openTransparency: () -> Void = {}
    @ObservationIgnored var onRequestStarted: () -> Void = {}
    @ObservationIgnored var onPhaseChanged: () -> Void = {}
    @ObservationIgnored private var session: AgentSession?
    @ObservationIgnored private var context: RequestContext?
    var currentRequestLabel: String? { context?.label }
    @ObservationIgnored private var dwellLocked: String?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var permissionPoll: Task<Void, Never>?
    @ObservationIgnored private var appInUse: NSRunningApplication?
    @ObservationIgnored private var appInUseObserver: NSObjectProtocol?
    @ObservationIgnored private var permissionObserver: NSObjectProtocol?
    @ObservationIgnored private var traceCounter = 0
    @ObservationIgnored private var auxiliaryCounter = 0
    @ObservationIgnored private let preview: Bool

    init(mode: AgentMode, settings: Settings, preview: Bool = false) {
        self.mode = mode
        self.settings = settings
        self.preview = preview
        speaker = Speaker(settings: settings)
        voice = VoiceInput()
        scanner = Scanner()
        accessibilityTrusted = preview || AXIsProcessTrusted()
        voice.onTranscript = { [weak self] text in self?.submitVoice(text) }
        voice.keyterms = { [weak self] in Vocabulary.recognitionKeyterms + (self?.settings.aliases.map(\.phrase) ?? []) }
        scanner.interval = { [weak self] in self?.settings.scanInterval ?? 1.4 }
        scanner.isPaused = { [weak self] in self?.interaction.isBusy ?? false }
        scanner.onCue = { [weak self] text in self?.announce(text, urgent: false) }
        settings.onSpeechChange = { [weak self] in
            self?.speaker.reloadKey()
            self?.speaker.prewarm()
        }
    }

    // MARK: - Agent session

    func start() {
        guard !preview else {
            interaction.connected()
            return
        }
        interaction.reconnecting()
        do {
            let session = AgentSession(configuration: try AgentLocator.configuration(mode: mode))
            session.onEvent = { [weak self] event in self?.handle(event) }
            try session.start()
            self.session = session
            interaction.connected()
        } catch let error as AgentLaunchError {
            note("The agent could not start: \(error.message) \(error.recovery)")
            perform(interaction.disconnected(FailureInfo(kind: .connection, message: error.message, detail: error.recovery, recovery: .restartAgent)))
        } catch {
            note("The agent could not start: \(error.localizedDescription)")
            perform(interaction.disconnected(FailureInfo(kind: .connection, message: "Nora’s agent couldn’t start.",
                                                         detail: error.localizedDescription, recovery: .restartAgent)))
        }
        speaker.prewarm()
        voice.prewarm()
        if settings.scanning { scanner.start() }
        if mode == .live { refreshPermission() }
        watchPermission()
        watchAppInUse()
    }

    /// macOS announces every change to the Accessibility list, including a switch flipped in System Settings.
    /// The new state takes a moment to apply, so look again shortly after.
    private func watchPermission() {
        guard permissionObserver == nil else { return }
        permissionObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self?.refreshPermission()
            }
        }
    }

    /// Zoom shortcuts are delivered to the frontmost app. Remember the app the person was using
    /// and hand it back before a zoom, in case Nora itself is in front.
    private func watchAppInUse() {
        guard appInUseObserver == nil else { return }
        noteAppInUse()
        appInUseObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.noteAppInUse() }
        }
    }

    private func noteAppInUse() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        appInUse = app
    }

    private func handFocusBackIfZooming(_ intent: String?) {
        guard intent == "ZOOM_IN" || intent == "ZOOM_OUT" else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
              let appInUse else { return }
        appInUse.activate()
    }

    func restart() {
        stopSession()
        start()
    }

    func switchMode(_ newMode: AgentMode) {
        guard newMode != mode else { return }
        if !preview { UserDefaults.standard.set(newMode.rawValue, forKey: "agentMode") }
        mode = newMode
        restart()
    }

    func shutdown() {
        if let appInUseObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appInUseObserver)
            self.appInUseObserver = nil
        }
        if let permissionObserver {
            DistributedNotificationCenter.default().removeObserver(permissionObserver)
            self.permissionObserver = nil
        }
        session?.onEvent = nil
        session?.stopAndWait()
        session = nil
    }

    private func stopSession() {
        session?.onEvent = nil
        session?.stop()
        session = nil
        agentPID = nil
        voice.cancel()
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .started(let pid):
            agentPID = pid
            note("Agent started in \(mode == .mock ? "practice" : "live") mode (process \(pid)).")
        case .sent(let request, let line):
            record(.sent, request.requestId, Self.summary(request), line)
        case .received(let message, let line):
            record(.received, message.requestId, Self.summary(message), line)
            if case .history(_, let entries) = message { history = entries }
            perform(interaction.receive(message))
            onPhaseChanged()
        case .diagnostic(let line):
            record(.diagnostic, nil, line, line)
        case .unreadable(let line):
            record(.diagnostic, nil, "Unreadable output from the agent", line)
        case .terminated(let status):
            agentPID = nil
            session = nil
            note("Agent stopped (exit status \(status)).")
            perform(interaction.disconnected(FailureInfo(kind: .connection, message: "Nora’s agent stopped.",
                                                         detail: "Press Restart to start it again.", recovery: .restartAgent)))
        }
    }

    // MARK: - Input

    func activate(_ tile: TileSpec, via method: String = "tile") {
        submit(.aac(tile.intent), RequestContext(modality: method, label: tile.title, intent: tile.intent,
                                                 noraActions: 1, noraOperators: InteractionCost.tileOperators))
    }

    func submitDraft() {
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength))
        guard !text.isEmpty else {
            requestedFocus = .textField
            return
        }
        let operators = InteractionCost.typedOperators(characters: text.count)
        let accepted: Bool
        if let intent = AliasResolver.intent(for: text, aliases: settings.aliases) {
            accepted = submit(.aac(intent), RequestContext(modality: "personal word", label: text, intent: intent,
                                                           noraActions: text.count + 1, noraOperators: operators))
            if accepted { note("Personal word “\(text)” means \(TileCatalog.tile(for: intent)?.title ?? intent).") }
        } else {
            accepted = submit(.text(text), RequestContext(modality: "text", label: text, intent: IntentEstimator.intent(forText: text),
                                                          noraActions: text.count + 1, noraOperators: operators))
        }
        if accepted { draft = "" }
    }

    func submitExample(_ phrase: String) {
        submit(.text(phrase), RequestContext(modality: "example", label: phrase, intent: IntentEstimator.intent(forText: phrase),
                                             noraActions: 1, noraOperators: InteractionCost.tileOperators))
    }

    func choose(_ suggestion: Suggestion) {
        submit(.aac(suggestion.intent), RequestContext(modality: "repair choice", label: suggestion.label, intent: suggestion.intent,
                                                       noraActions: 1, noraOperators: InteractionCost.tileOperators))
    }

    func toggleVoice() {
        guard voice.isBusy || interaction.acceptsInput else { return }
        voice.toggle()
        if voice.isListening { announce("Listening.", urgent: false) }
    }

    /// Summoning Nora with a double tap of Command starts listening, so a spoken request needs no button press.
    /// There is no spoken “Listening.” cue: the microphone would hear it and treat it as the request.
    func listenOnSummon() {
        guard interaction.acceptsInput, interaction.pendingConfirmation == nil, !voice.isBusy else { return }
        speaker.stop()
        voice.toggle()
    }

    /// Putting Nora away stops a recording in progress; words already recorded still get transcribed and run.
    func stopListening() {
        if voice.isListening { voice.cancel() }
    }

    private func submitVoice(_ transcript: String) {
        note("Heard “\(transcript)” using \(voice.lastEngine).")
        if let milliseconds = voice.lastSpeechToTranscriptMs {
            note("Speech handoff took \(milliseconds) ms after the last detected speech.")
        }
        let context = RequestContext(modality: "voice", label: transcript, intent: IntentEstimator.intent(forText: transcript),
                                     noraActions: 1, noraOperators: InteractionCost.tileOperators)
        if let intent = AliasResolver.intent(for: transcript, aliases: settings.aliases) {
            var aliased = context
            aliased.modality = "voice (personal word)"
            aliased.intent = intent
            submit(.aac(intent), aliased)
        } else {
            submit(.voice(transcript), context)
        }
    }

    func decide(approved: Bool) {
        let effects = interaction.decide(approved: approved)
        guard !effects.isEmpty else { return }
        if approved { onRequestStarted() }
        context?.noraActions += 1
        context?.noraOperators += KLM.click
        perform(effects)
    }

    func askAgain() {
        guard let input = interaction.lastInput else { return }
        submit(input, RequestContext(modality: "ask again", label: Self.label(for: input), intent: IntentEstimator.intent(for: input),
                                     noraActions: 1, noraOperators: InteractionCost.tileOperators))
    }

    func dismiss() {
        voice.clearFailure()
        interaction.dismiss()
    }

    @discardableResult
    private func submit(_ input: UserInput, _ context: RequestContext) -> Bool {
        if voice.isBusy { voice.cancel() }
        voice.clearFailure()
        let effects = interaction.submit(input)
        guard !effects.isEmpty else { return false }
        handFocusBackIfZooming(context.intent)
        self.context = context
        onRequestStarted()
        perform(effects)
        return true
    }

    // MARK: - Effects

    private func perform(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .send(let request):
                guard let session else { continue }
                do {
                    try session.send(request)
                } catch {
                    stopSession()
                    perform(interaction.disconnected(FailureInfo(kind: .connection, message: "Nora couldn’t reach its agent.",
                                                                 detail: error.localizedDescription, recovery: .restartAgent)))
                }
            case .announce(let text, let urgent):
                announce(text, urgent: urgent)
            case .completed(let completed):
                complete(completed)
            }
        }
    }

    private func complete(_ completed: CompletedRequest) {
        let context = self.context ?? RequestContext(
            modality: completed.input.source, label: Self.label(for: completed.input),
            intent: IntentEstimator.intent(for: completed.input), noraActions: 1, noraOperators: InteractionCost.tileOperators)
        self.context = nil
        evaluation.record(completed, modality: context.modality, request: context.label, intent: context.intent, noraActions: context.noraActions)
        if completed.outcome == .succeeded, let intent = context.intent {
            tally.record(intent: intent, noraOperators: context.noraOperators, noraActions: context.noraActions,
                         agentSeconds: completed.finishedAt.timeIntervalSince(completed.startedAt))
        }
        if case .failed(let failure) = interaction.phase, let first = failure.suggestions.first {
            requestedFocus = .suggestion(first.intent)
        }
    }

    /// Status changes go to VoiceOver as announcements (they never move focus) and to spoken feedback.
    func announce(_ text: String, urgent: Bool) {
        guard !preview else { return }
        let priority: NSAccessibilityPriorityLevel = urgent ? .high : .medium
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: priority.rawValue])
        speaker.speak(text)
    }

    // MARK: - Access methods

    func hover(_ tile: TileSpec, inside: Bool) {
        guard settings.dwell else { return }
        if inside {
            guard dwellLocked != tile.id, interaction.acceptsInput else { return }
            dwellTask?.cancel()
            dwellTarget = tile.id
            dwellStartedAt = Date()
            let wait = settings.dwellSeconds
            dwellTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self, self.dwellTarget == tile.id else { return }
                self.dwellTarget = nil
                self.dwellStartedAt = nil
                // The pointer has to leave before this tile can fire again, so resting on it never repeats.
                self.dwellLocked = tile.id
                self.activate(tile, via: "dwell")
            }
        } else {
            if dwellTarget == tile.id {
                dwellTask?.cancel()
                dwellTarget = nil
                dwellStartedAt = nil
            }
            if dwellLocked == tile.id { dwellLocked = nil }
        }
    }

    func setScanning(_ enabled: Bool) {
        settings.scanning = enabled
        if enabled { scanner.start() } else { scanner.stop() }
    }

    func switchPressed() {
        if let tile = scanner.press(), interaction.acceptsInput {
            activate(tile, via: "switch scanning")
        }
    }

    /// Single-key shortcuts while the panel has keyboard focus. Returns true when the key was used.
    func handleKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, editingText: Bool) -> Bool {
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        if keyCode == 53 {
            if interaction.pendingConfirmation != nil {
                decide(approved: false)
            } else if voice.isBusy {
                voice.cancel()
            } else if editingText && !draft.isEmpty {
                draft = ""
            } else {
                dismiss()
            }
            return true
        }
        guard !editingText else { return false }
        if characters == " " && settings.scanning {
            switchPressed()
            return true
        }
        if characters == "/" {
            requestedFocus = .textField
            return true
        }
        let tile = TileCatalog.all.first { $0.shortcut == characters } ?? (characters == "+" ? TileCatalog.tile(for: "ZOOM_IN") : nil)
        guard let tile else { return false }
        if interaction.acceptsInput { activate(tile, via: "keyboard shortcut") }
        return true
    }

    // MARK: - Permissions

    func refreshPermission() {
        accessibilityTrusted = preview || AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        accessibilityTrusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openSystemSettings("Privacy_Accessibility")
        permissionPoll?.cancel()
        permissionPoll = Task { [weak self] in
            for _ in 0..<150 {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.refreshPermission()
                if self.accessibilityTrusted { return }
            }
        }
    }

    func openMicrophoneSettings() {
        openSystemSettings("Privacy_Microphone")
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func runPermissionCheck(saveReport: Bool = false) {
        Task { [weak self] in
            let report = await Diagnostics.checkPermissionChain()
            if saveReport { Diagnostics.writeReport(report) }
            self?.permissionReport = report
            self?.note(report.summary)
        }
    }

    // MARK: - Transparency and measurement

    func refreshHistory() {
        sendAuxiliary(.getHistory(requestId: nextAuxiliaryId("history")))
    }

    func clearHistory() {
        sendAuxiliary(.clearHistory(requestId: nextAuxiliaryId("clear-history")))
    }

    private func sendAuxiliary(_ request: AgentRequest) {
        try? session?.send(request)
    }

    private func nextAuxiliaryId(_ prefix: String) -> String {
        auxiliaryCounter += 1
        return "\(prefix)-\(auxiliaryCounter)-\(UUID().uuidString.prefix(6).lowercased())"
    }

    func exportEvaluation() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nora Evaluations", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let file = folder.appendingPathComponent("nora-evaluation-\(formatter.string(from: Date())).csv")
            try evaluation.csv().write(to: file, atomically: true, encoding: .utf8)
            exportedEvaluation = file
            note("Saved the evaluation log to \(file.path).")
        } catch {
            note("Could not save the evaluation log: \(error.localizedDescription)")
        }
    }

    func revealExport() {
        if let exportedEvaluation { NSWorkspace.shared.activateFileViewerSelecting([exportedEvaluation]) }
    }

    func resetMeasurements() {
        evaluation.clear()
        tally.reset()
    }

    func note(_ text: String) {
        record(.note, nil, text, "")
    }

    private func record(_ direction: TraceEntry.Direction, _ requestId: String?, _ summary: String, _ raw: String) {
        traceCounter += 1
        trace.append(TraceEntry(id: traceCounter, time: Date(), direction: direction, requestId: requestId, summary: summary, raw: raw))
        if trace.count > 500 { trace.removeFirst(trace.count - 500) }
    }

    static func label(for input: UserInput) -> String {
        switch input {
        case .aac(let intent): TileCatalog.tile(for: intent)?.title ?? intent
        case .text(let text), .voice(let text): text
        }
    }

    static func summary(_ request: AgentRequest) -> String {
        switch request {
        case .submit(_, .aac(let intent)): "Tile \(intent)"
        case .submit(_, .text(let text)): "Typed “\(text)”"
        case .submit(_, .voice(let text)): "Spoken “\(text)”"
        case .confirm(_, _, let approved): approved ? "Confirm the pending action" : "Cancel the pending action"
        case .getHistory: "Ask for the action history"
        case .clearHistory: "Clear the action history"
        }
    }

    static func summary(_ message: AgentMessage) -> String {
        switch message {
        case .event(_, let event):
            switch event {
            case .listening: return "listening"
            case .thinking(let message): return "thinking" + (message.map { ": \($0)" } ?? "")
            case .acting(let message): return "acting: \(message)"
            case .confirmationRequired(let prompt): return "needs confirmation (\(prompt.risk.rawValue)): \(ActionDescriber.headline(prompt))"
            case .confirmationResolved(_, let reason): return "confirmation \(reason.rawValue)"
            case .done(let message): return "done" + (message.map { ": \($0)" } ?? "")
            case .error(let message): return "error: \(message)"
            case .unrecognized(let type): return "unrecognized event “\(type)”"
            }
        case .result(_, let result):
            switch result {
            case .success(let message): return "result: success" + (message.map { " — \($0)" } ?? "")
            case .failure(let error): return "result: failed — \(error)"
            case .needsConfirmation: return "result: waiting for confirmation"
            }
        case .history(_, let entries):
            return "history: \(entries.count) action\(entries.count == 1 ? "" : "s")"
        case .protocolError(_, let error):
            return "protocol error: \(error)"
        }
    }

    // MARK: - Previews

    /// Drives the real state machine with scripted agent replies, for snapshots and demos without a process.
    func simulate(_ input: UserInput, replies: (String) -> [AgentMessage]) {
        guard preview else { return }
        let effects = interaction.submit(input)
        guard case .send(let request)? = effects.first else { return }
        context = RequestContext(modality: input.source == "aac" ? "tile" : input.source, label: Self.label(for: input),
                                 intent: IntentEstimator.intent(for: input), noraActions: 1, noraOperators: InteractionCost.tileOperators)
        handle(.sent(request, line: ""))
        for message in replies(request.requestId) { handle(.received(message, line: "")) }
    }
}
