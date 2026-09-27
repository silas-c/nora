import Foundation

public enum AgentMode: String, Sendable, CaseIterable, Identifiable {
    /// The real agent and transport against the synthetic Canvas controller. Nothing on the Mac changes.
    case mock
    /// The production server with the Swift helper. Nora controls this Mac.
    case live

    public var id: String { rawValue }
}

public struct AgentLaunchConfiguration: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var workingDirectory: URL
    public var mode: AgentMode

    public init(executable: URL, arguments: [String], workingDirectory: URL, mode: AgentMode) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.mode = mode
    }
}

public struct AgentLaunchError: LocalizedError, Equatable, Sendable {
    public var message: String
    public var recovery: String

    public init(message: String, recovery: String) {
        self.message = message
        self.recovery = recovery
    }

    public var errorDescription: String? { message }
    public var recoverySuggestion: String? { recovery }
}

public enum AgentLocator {
    public static func repositoryRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleValue: String? = Bundle.main.object(forInfoDictionaryKey: "NoraRepoRoot") as? String,
        sourceFile: String = #filePath
    ) -> URL? {
        var candidates = [environment["NORA_REPO_ROOT"], bundleValue]
            .compactMap { $0 }
            .map { URL(fileURLWithPath: $0) }
        // Sources/NoraCore/AgentLaunch.swift sits five levels below the repository root.
        var root = URL(fileURLWithPath: sourceFile)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        candidates.append(root)
        return candidates.first(where: isRepositoryRoot)
    }

    public static func isRepositoryRoot(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("packages/agent/package.json").path)
    }

    public static func nodeExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default
        if let override = environment["NORA_NODE"], fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "\(home)/.volta/bin/node"]
        candidates += nvmNodes(home: home)
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/node" }
        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }

    private static func nvmNodes(home: String) -> [String] {
        let versions = "\(home)/.nvm/versions/node"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versions)) ?? []
        func components(_ name: String) -> [Int] {
            name.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").compactMap { Int($0) }
        }
        return names
            .sorted { components($0).lexicographicallyPrecedes(components($1)) }
            .reversed()
            .map { "\(versions)/\($0)/bin/node" }
    }

    public static func configuration(
        mode: AgentMode,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        repositoryRoot explicitRoot: URL? = nil
    ) throws -> AgentLaunchConfiguration {
        guard let root = explicitRoot ?? repositoryRoot(environment: environment) else {
            throw AgentLaunchError(message: "Nora couldn’t find its project folder.",
                                   recovery: "Set NORA_REPO_ROOT to the path of the nora repository.")
        }
        guard let node = nodeExecutable(environment: environment) else {
            throw AgentLaunchError(message: "Node.js isn’t installed where Nora can find it.",
                                   recovery: "Install Node.js 22 or newer, or set NORA_NODE to its path.")
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.appendingPathComponent("dist/agent/src/index.js").path) else {
            throw AgentLaunchError(message: "The agent hasn’t been built yet.",
                                   recovery: "In the nora folder, run: npm ci && npm run build")
        }
        switch mode {
        case .mock:
            let script = root.appendingPathComponent("apps/desktop-ui/scripts/mock-agent-server.mjs")
            return AgentLaunchConfiguration(executable: node, arguments: ["--env-file-if-exists=.env.local", script.path], workingDirectory: root, mode: mode)
        case .live:
            let helper = root.appendingPathComponent("apps/macos-helper/.build/debug/mac-helper")
            guard fileManager.isExecutableFile(atPath: helper.path) else {
                throw AgentLaunchError(message: "The macOS helper hasn’t been built yet.",
                                       recovery: "In the nora folder, run: swift build --package-path apps/macos-helper")
            }
            let server = root.appendingPathComponent("dist/agent/src/server.js")
            return AgentLaunchConfiguration(executable: node, arguments: ["--env-file-if-exists=.env.local", server.path, "--native"], workingDirectory: root, mode: mode)
        }
    }
}
