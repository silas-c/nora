import AppKit
import NoraCore
import SwiftUI

/// `nora-ui --snapshot <folder>` renders each interface state to PNG with the real views and state machine,
/// driven by scripted agent replies. Useful for reviewing layout and for demo slides.
@MainActor
enum SnapshotRenderer {
    private struct Scene {
        var name: String
        var mode: AgentMode = .mock
        var scale: Double = 1
        var dark = false
        var height: CGFloat = 710
        var setup: (AppModel) -> Void = { _ in }
    }

    private static let canvasDone = "Canvas open request sent to Microsoft Edge."
    private static let unknownHint = "Try “Open Canvas”, “Show me dog photos”, or “Make text bigger”."

    private static func succeed(_ model: AppModel, _ tile: String, acting: String, done: String) {
        model.simulate(.aac(tile)) { id in
            [.event(requestId: id, .thinking(nil)), .event(requestId: id, .acting(acting)),
             .event(requestId: id, .done(done)), .result(requestId: id, .success(done))]
        }
    }

    private static let confirmPrompt = ConfirmationRequest(
        id: "preview", message: "Delete everything in your Downloads folder (practice only — no files are touched) Action: {}",
        action: ComputerAction(type: "launch_app", app: "Mock deletion executor"), risk: .destructive,
        expiresAt: Date().addingTimeInterval(60))

    private static var scenes: [Scene] {
        [
            Scene(name: "01-ready"),
            Scene(name: "02-acting") { model in
                model.simulate(.aac("OPEN_SCHOOL")) { id in
                    [.event(requestId: id, .thinking(nil)), .event(requestId: id, .acting("Opening Canvas in Microsoft Edge…"))]
                }
            },
            Scene(name: "03-done") { model in
                succeed(model, "OPEN_COURSES", acting: "Opening the visible Courses control…", done: "Courses is visible in Canvas.")
                succeed(model, "OPEN_SCHOOL", acting: "Opening Canvas in Microsoft Edge…", done: canvasDone)
            },
            Scene(name: "04-repair") { model in
                model.simulate(.text("open my canvs")) { id in
                    [.event(requestId: id, .thinking(nil)), .event(requestId: id, .error(unknownHint)), .result(requestId: id, .failure(unknownHint))]
                }
            },
            Scene(name: "05-confirm") { model in
                model.simulate(.text("Delete everything in Downloads")) { id in
                    [.event(requestId: id, .thinking(nil)), .event(requestId: id, .confirmationRequired(confirmPrompt)),
                     .result(requestId: id, .needsConfirmation(id: confirmPrompt.id, message: confirmPrompt.message))]
                }
            },
            Scene(name: "06-live-error", mode: .live) { model in
                let error = "Unable to find application named 'Microsoft Edge'"
                model.simulate(.aac("OPEN_SCHOOL")) { id in
                    [.event(requestId: id, .acting("Opening Canvas in Microsoft Edge…")), .event(requestId: id, .error(error)),
                     .result(requestId: id, .failure(error))]
                }
            },
            Scene(name: "07-confirm-dark", dark: true) { model in
                model.simulate(.text("Delete everything in Downloads")) { id in
                    [.event(requestId: id, .confirmationRequired(confirmPrompt))]
                }
            },
            Scene(name: "08-ready-dark", dark: true) { model in
                succeed(model, "ZOOM_IN", acting: "Sending zoom-in shortcut to the active app…", done: "Zoom-in shortcut sent to the active app.")
            },
            Scene(name: "09-scanning") { model in model.setScanning(true) },
            Scene(name: "10-large-text", scale: 1.5, height: 1065),
        ]
    }

    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var lastModel: AppModel?
        for scene in scenes {
            let settings = Settings(defaults: nil)
            settings.scale = scene.scale
            let model = AppModel(mode: scene.mode, settings: settings, preview: true)
            model.start()
            scene.setup(model)
            // Snapshots have no desktop behind the transparent panel, so give them a neutral backdrop.
            write(RootView(model: model).background(Color(nsColor: .windowBackgroundColor)),
                  size: NSSize(width: 820 * scene.scale, height: scene.height),
                  dark: scene.dark, to: directory.appendingPathComponent("\(scene.name).png"))
            model.scanner.stop()
            lastModel = model
        }

        let activity = AppModel(mode: .mock, settings: Settings(defaults: nil), preview: true)
        activity.start()
        succeed(activity, "OPEN_SCHOOL", acting: "Opening Canvas in Microsoft Edge…", done: canvasDone)
        activity.simulate(.text("open my canvs")) { id in
            [.event(requestId: id, .error(unknownHint)), .result(requestId: id, .failure(unknownHint))]
        }
        write(TransparencyView(model: activity), size: NSSize(width: 660, height: 900), dark: false,
              to: directory.appendingPathComponent("11-activity.png"))
        if let lastModel {
            write(SettingsView(model: lastModel), size: NSSize(width: 620, height: 1100), dark: false,
                  to: directory.appendingPathComponent("12-settings.png"))
        }
    }

    private static func write<V: View>(_ view: V, size: NSSize, dark: Bool, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
