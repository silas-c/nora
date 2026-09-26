import Foundation

struct Request: Decodable {
    let type: String
    let url: String?
    let browser: String?
}

struct Response: Encodable {
    let success: Bool
    let error: String?

    static let ok = Response(success: true, error: nil)

    static func failure(_ message: String) -> Response {
        Response(success: false, error: message)
    }
}

func handle(_ line: String) -> Response {
    let request: Request
    do {
        request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
    } catch {
        return .failure("Invalid request JSON: \(error.localizedDescription)")
    }

    guard request.type == "open_url" else {
        return .failure("Unsupported action: \(request.type)")
    }
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

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = arguments
    let standardError = Pipe()
    process.standardError = standardError

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return .failure("Could not launch browser: \(error.localizedDescription)")
    }

    guard process.terminationStatus == 0 else {
        let output = standardError.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(detail?.isEmpty == false ? detail! : "Browser exited with status \(process.terminationStatus)")
    }
    return .ok
}

let encoder = JSONEncoder()
while let line = readLine() {
    let response = handle(line)
    if let data = try? encoder.encode(response) {
        FileHandle.standardOutput.write(data + Data([0x0A]))
    }
}
