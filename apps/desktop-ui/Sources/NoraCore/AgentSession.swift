import Foundation

public enum SessionEvent: Sendable, Equatable {
    case started(pid: Int32)
    case sent(AgentRequest, line: String)
    case received(AgentMessage, line: String)
    /// A diagnostic line the agent wrote to stderr.
    case diagnostic(String)
    /// A stdout line that was not a valid protocol message.
    case unreadable(String)
    case terminated(status: Int32)
}

public struct SessionError: LocalizedError, Sendable {
    public var message: String
    public var errorDescription: String? { message }
}

/// Owns one agent server process and its JSON-lines connection.
/// One session is one agent plus one helper session; closing stdin cancels outstanding work.
@MainActor
public final class AgentSession {
    public let configuration: AgentLaunchConfiguration
    public var onEvent: ((SessionEvent) -> Void)?
    public private(set) var isRunning = false

    private var process: Process?
    private var input: FileHandle?
    private var stdoutFramer = LineFramer()
    private var stderrFramer = LineFramer()
    private var outputClosed = false
    private var exitStatus: Int32?
    private var reported = false

    public init(configuration: AgentLaunchConfiguration) {
        self.configuration = configuration
    }

    public var processIdentifier: Int32? { process?.processIdentifier }

    public func start() throws {
        guard process == nil else { return }
        // A closed pipe must surface as a thrown write error, not terminate the app.
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = configuration.executable
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.workingDirectory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let outputChunks = Self.chunks(from: stdout.fileHandleForReading)
        let errorChunks = Self.chunks(from: stderr.fileHandleForReading)
        let (exits, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
        isRunning = true
        onEvent?(.started(pid: process.processIdentifier))

        Task { [weak self] in
            for await chunk in outputChunks { self?.receiveOutput(chunk) }
            self?.outputFinished()
        }
        Task { [weak self] in
            for await chunk in errorChunks { self?.receiveDiagnostics(chunk) }
        }
        Task { [weak self] in
            for await status in exits { self?.processExited(status) }
        }
    }

    public func send(_ request: AgentRequest) throws {
        guard isRunning, let input else { throw SessionError(message: "Nora’s agent isn’t running.") }
        let data = try AgentCodec.encodeLine(request)
        do {
            try input.write(contentsOf: data)
        } catch {
            throw SessionError(message: "Nora couldn’t reach its agent.")
        }
        onEvent?(.sent(request, line: String(decoding: data.dropLast(), as: UTF8.self)))
    }

    /// Closes stdin so the server cancels active work and closes the helper, then terminates if needed.
    public func stop(grace: Duration = .seconds(2)) {
        guard process != nil else { return }
        try? input?.close()
        input = nil
        isRunning = false
        Task { [weak self] in
            try? await Task.sleep(for: grace)
            self?.terminateIfRunning()
        }
    }

    /// Synchronous shutdown for app termination, when no further run-loop turns are guaranteed.
    public func stopAndWait(timeout: TimeInterval = 1.5) {
        guard let process else { return }
        try? input?.close()
        input = nil
        isRunning = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate() }
    }

    private func terminateIfRunning() {
        if let process, process.isRunning { process.terminate() }
    }

    nonisolated private static func chunks(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
    }

    private func receiveOutput(_ chunk: Data) {
        for line in stdoutFramer.append(chunk) where !line.isEmpty {
            let text = String(decoding: line, as: UTF8.self)
            if let message = try? AgentCodec.decode(line: line) {
                onEvent?(.received(message, line: text))
            } else {
                onEvent?(.unreadable(text))
            }
        }
    }

    private func receiveDiagnostics(_ chunk: Data) {
        for line in stderrFramer.append(chunk) where !line.isEmpty {
            onEvent?(.diagnostic(String(decoding: line, as: UTF8.self)))
        }
    }

    private func outputFinished() {
        outputClosed = true
        reportTerminationIfComplete()
    }

    private func processExited(_ status: Int32) {
        exitStatus = status
        reportTerminationIfComplete()
        // A grandchild holding stdout open must not hide the exit from the UI.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.outputClosed = true
            self?.reportTerminationIfComplete()
        }
    }

    private func reportTerminationIfComplete() {
        guard outputClosed, let exitStatus, !reported else { return }
        reported = true
        isRunning = false
        input = nil
        process = nil
        onEvent?(.terminated(status: exitStatus))
    }
}
