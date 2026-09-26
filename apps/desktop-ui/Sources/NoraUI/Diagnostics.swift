import AppKit
import ApplicationServices
import Darwin
import NoraCore

struct PermissionReport: Sendable, Equatable {
    var noraPID: Int32
    var noraPath: String?
    var noraTrusted: Bool
    var chainResponsiblePID: Int32?
    var chainResponsiblePath: String?
    var helperTrusted: Bool?
    var error: String?

    var chainAttributedToNora: Bool { chainResponsiblePID == noraPID }

    var summary: String {
        if let error { return "Permission check could not finish: \(error)" }
        var parts = [chainAttributedToNora
            ? "macOS charges the Nora → node → helper chain to Nora, so granting Nora Accessibility covers the helper."
            : "macOS charges the helper chain to \(chainResponsiblePath ?? "another process") (pid \(chainResponsiblePID.map(String.init) ?? "?")), not to Nora."]
        parts.append(noraTrusted ? "Nora has Accessibility permission." : "Nora does not have Accessibility permission yet.")
        if let helperTrusted {
            parts.append(helperTrusted ? "The helper sees the permission." : "The helper does not see the permission yet.")
        }
        return parts.joined(separator: " ")
    }
}

enum Diagnostics {
    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// The process that macOS privacy checks (TCC) hold responsible for `pid`. Private libSystem API, diagnostic use only.
    static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)(pid)
    }

    static func path(for pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// `nora-ui --probe-responsibility` prints which process macOS holds responsible for this one.
    static func printResponsibility() {
        let pid = getpid()
        let responsible = responsiblePID(for: pid) ?? -1
        let object: [String: Any] = ["pid": pid, "responsible": responsible, "responsiblePath": path(for: responsible) ?? ""]
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        }
    }

    /// Recreates the production chain (Nora → node → child process) and asks the child who macOS holds responsible.
    static func checkPermissionChain() async -> PermissionReport {
        let noraPID = getpid()
        let trusted = AXIsProcessTrusted()
        let noraPath = path(for: noraPID)
        guard let root = AgentLocator.repositoryRoot(), let node = AgentLocator.nodeExecutable(),
              let executable = Bundle.main.executableURL else {
            return PermissionReport(noraPID: noraPID, noraPath: noraPath, noraTrusted: trusted, error: "Node.js or the nora folder could not be found.")
        }
        let helper = root.appendingPathComponent("apps/macos-helper/.build/debug/mac-helper")
        return await Task.detached {
            var report = PermissionReport(noraPID: noraPID, noraPath: noraPath, noraTrusted: trusted)
            let probe = "const {execFileSync}=require('node:child_process');process.stdout.write(execFileSync(process.argv[1],['--probe-responsibility']));"
            if let output = run(node, ["-e", probe, executable.path]),
               let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any] {
                report.chainResponsiblePID = (json["responsible"] as? NSNumber)?.int32Value
                report.chainResponsiblePath = json["responsiblePath"] as? String
            } else {
                report.error = "The node probe did not run."
            }
            if FileManager.default.isExecutableFile(atPath: helper.path) {
                let state = "const {execFileSync}=require('node:child_process');process.stdout.write(execFileSync(process.argv[1],{input:'{\"type\":\"get_state\"}\\n'}));"
                if let output = run(node, ["-e", state, helper.path]),
                   let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any] {
                    report.helperTrusted = json["accessibilityTrusted"] as? Bool
                }
            }
            return report
        }.value
    }

    private static func run(_ executable: URL, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// `--diagnose`: runs the chain check from inside the launched app and writes the result for scripts to read.
    static func writeReport(_ report: PermissionReport) {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Nora", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let object: [String: Any] = [
            "noraPID": report.noraPID,
            "noraPath": report.noraPath ?? "",
            "noraTrusted": report.noraTrusted,
            "chainResponsiblePID": report.chainResponsiblePID.map { Int($0) } ?? -1,
            "chainResponsiblePath": report.chainResponsiblePath ?? "",
            "chainAttributedToNora": report.chainAttributedToNora,
            "helperTrusted": report.helperTrusted.map { $0 as Any } ?? NSNull(),
            "summary": report.summary,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: logs.appendingPathComponent("permission-check.json"))
        }
    }
}
