import AppKit
import Foundation

struct Request: Decodable {
    let type: String
    let url: String?
    let browser: String?
    let app: String?
    let target: String?
    let snapshotGeneration: String?
    let expectedApp: String?
    let expectedWindow: String?
    let expectedRole: String?
    let expectedLabel: String?
    let expectedActions: [String]?
    let text: String?
    let key: String?
    let modifiers: [String]?
    let direction: String?
    let amount: Int?
}

struct Response: Encodable {
    let success: Bool
    var error: String? = nil
    var activeApp: String? = nil
    var snapshotGeneration: String? = nil
    var activeWindow: String? = nil
    var accessibilityTrusted: Bool? = nil
    var elements: [ElementSnapshot]? = nil
    var truncated: Bool? = nil

    static let ok = Response(success: true)

    static func failure(_ message: String) -> Response {
        Response(success: false, error: message)
    }
}

struct ExpectedTarget {
    let app: String
    let window: String?
    let role: String
    let label: String?
    let actions: [String]
}

func expectedTarget(_ request: Request) -> ExpectedTarget? {
    guard let app = request.expectedApp,
          let role = request.expectedRole,
          let actions = request.expectedActions else { return nil }
    return ExpectedTarget(app: app, window: request.expectedWindow, role: role,
                          label: request.expectedLabel, actions: actions)
}

func runOpen(_ arguments: [String]) -> Response {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    let standardError = Pipe()
    process.standardError = standardError

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return .failure("Could not open target: \(error.localizedDescription)")
    }

    guard process.terminationStatus == 0 else {
        let output = standardError.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return .failure(detail)
        }
        return .failure("open exited with status \(process.terminationStatus)")
    }
    return .ok
}

@MainActor func handle(_ line: String) -> Response {
    let request: Request
    do {
        request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
    } catch {
        return .failure("Invalid request JSON: \(error.localizedDescription)")
    }

    switch request.type {
    case "open_url":
        guard let rawURL = request.url,
              let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            return .failure("open_url requires a valid http or https URL")
        }
        var arguments = [String]()
        if let browser = request.browser, !browser.isEmpty {
            arguments += ["-a", browser]
        }
        arguments.append(url.absoluteString)
        return runOpen(arguments)

    case "launch_app":
        guard let app = request.app?.trimmingCharacters(in: .whitespacesAndNewlines),
              !app.isEmpty else {
            return .failure("launch_app requires an app name")
        }
        return runOpen(["-a", app])

    case "focus_app":
        guard let name = request.app?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .failure("focus_app requires an app name")
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return .failure("App is not running: \(name)")
        }
        return app.activate(options: []) ? .ok : .failure("Could not focus app: \(name)")

    case "get_state":
        guard let name = NSWorkspace.shared.frontmostApplication?.localizedName else {
            return .failure("Could not determine the active app")
        }
        return Response(success: true, activeApp: name, accessibilityTrusted: AXIsProcessTrusted())

    case "default_browser":
        // The app named like its .app file, matching the installed app names the agent lists.
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            return .failure("No default browser is set")
        }
        return Response(success: true, activeApp: url.deletingPathExtension().lastPathComponent)

    case "snapshot":
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .failure("Could not determine the active app")
        }
        do {
            let snapshot = try snapshotReader.read(app)
            return Response(success: true, activeApp: snapshot.activeApp, snapshotGeneration: snapshot.snapshotGeneration,
                            activeWindow: snapshot.activeWindow,
                            accessibilityTrusted: true, elements: snapshot.elements, truncated: snapshot.truncated)
        } catch {
            return Response(success: false, error: error.localizedDescription,
                            activeApp: app.localizedName, accessibilityTrusted: AXIsProcessTrusted())
        }

    case "click":
        guard let target = request.target,
              let generation = request.snapshotGeneration else {
            return .failure("click requires a target ID and snapshotGeneration")
        }
        do {
            try snapshotReader.click(target, generation: generation, expected: expectedTarget(request))
            return .ok
        } catch {
            return .failure(error.localizedDescription)
        }

    case "type_text":
        guard let text = request.text else { return .failure("type_text requires text") }
        do {
            if let target = request.target {
                guard let generation = request.snapshotGeneration else {
                    return .failure("targeted type_text requires snapshotGeneration")
                }
                try snapshotReader.setText(text, in: target, generation: generation, expected: expectedTarget(request))
            } else {
                try typeFocusedText(text)
            }
            return .ok
        } catch {
            return .failure(error.localizedDescription)
        }

    case "keypress":
        guard let key = request.key else { return .failure("keypress requires a key") }
        do {
            try pressKey(key, modifiers: request.modifiers ?? [])
            return .ok
        } catch {
            return .failure(error.localizedDescription)
        }

    case "scroll":
        guard let direction = request.direction else { return .failure("scroll requires a direction") }
        do {
            try scroll(direction, amount: request.amount ?? 3)
            return .ok
        } catch {
            return .failure(error.localizedDescription)
        }

    default:
        return .failure("Unsupported action: \(request.type)")
    }
}

let snapshotReader = SnapshotReader()
let encoder = JSONEncoder()
while let line = readLine() {
    let response = handle(line)
    if let data = try? encoder.encode(response) {
        FileHandle.standardOutput.write(data + Data([0x0A]))
    }
}
snapshotReader.stop()
