import AppKit

if CommandLine.arguments.contains("--probe-responsibility") {
    Diagnostics.printResponsibility()
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(CommandLine.arguments.contains("--snapshot") ? .prohibited : .accessory)
application.run()
