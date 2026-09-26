import AppKit
import Foundation

struct Request: Decodable {
    let type: String
    let url: String?
    let browser: String?
    let app: String?
    let target: String?
    let text: String?
    let key: String?
    let modifiers: [String]?
}

struct Response: Encodable {
    let success: Bool
    var error: String? = nil
    var activeApp: String? = nil
    var activeWindow: String? = nil
    var accessibilityTrusted: Bool? = nil
    var elements: [ElementSnapshot]? = nil
    var truncated: Bool? = nil

    static let ok = Response(success: true)

    static func failure(_ message: String) -> Response {
        Response(success: false, error: message)
    }
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

    case "get_state":
        guard let name = NSWorkspace.shared.frontmostApplication?.localizedName else {
            return .failure("Could not determine the active app")
        }
        return Response(success: true, activeApp: name, accessibilityTrusted: AXIsProcessTrusted())

    case "snapshot":
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .failure("Could not determine the active app")
        }
        do {
            let snapshot = try snapshotReader.read(app)
            return Response(success: true, activeApp: snapshot.activeApp, activeWindow: snapshot.activeWindow,
                            accessibilityTrusted: true, elements: snapshot.elements, truncated: snapshot.truncated)
        } catch {
            return Response(success: false, error: error.localizedDescription,
                            activeApp: app.localizedName, accessibilityTrusted: AXIsProcessTrusted())
        }

    case "click":
        guard let target = request.target else { return .failure("click requires a target ID") }
        do {
            try snapshotReader.click(target)
            return .ok
        } catch {
            return .failure(error.localizedDescription)
        }

    case "type_text":
        guard let text = request.text else { return .failure("type_text requires text") }
        do {
            if let target = request.target {
                try snapshotReader.setText(text, in: target)
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
