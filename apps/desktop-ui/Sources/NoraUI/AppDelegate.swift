import AppKit
import Carbon
import NoraCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let baseSize = NSSize(width: 820, height: 710)

    private var model: AppModel?
    private var panel: OverlayPanel?
    private var transparencyPanel: OverlayPanel?
    private var settingsPanel: OverlayPanel?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot") {
            let path = arguments.indices.contains(index + 1) ? arguments[index + 1] : "snapshots"
            SnapshotRenderer.render(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
            return
        }

        let stored = UserDefaults.standard.string(forKey: "agentMode").flatMap(AgentMode.init(rawValue:))
        let mode: AgentMode = arguments.contains("--live") ? .live : arguments.contains("--mock") ? .mock : (stored ?? .mock)
        let settings = Settings()
        let model = AppModel(mode: mode, settings: settings)
        self.model = model
        model.openSettings = { [weak self] in self?.showSettings() }
        model.openTransparency = { [weak self] in self?.showTransparency() }
        settings.onScaleChange = { [weak self] scale in self?.resizePanel(for: scale) }

        installMainMenu()
        installStatusItem()
        showMainPanel(model)
        installKeyMonitor()
        hotKey = HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak self] in self?.summon() }
        if hotKey == nil { model.note("Option-Space is taken by another app, so the Nora shortcut is off.") }
        model.start()
        if arguments.contains("--diagnose") { model.runPermissionCheck(saveReport: true) }
        if let index = arguments.firstIndex(of: "--self-test"), let panel {
            let path = arguments.indices.contains(index + 1) ? arguments[index + 1] : NSTemporaryDirectory() + "nora-self-test"
            Task { await SelfTest.run(model: model, panel: panel, directory: URL(fileURLWithPath: path), quitWhenDone: !arguments.contains("--stay")) }
        }

        // Opening an app activates it once; hand focus straight back so the app in use stays frontmost.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if NSApp.isActive { NSApp.deactivate() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Windows

    private func showMainPanel(_ model: AppModel) {
        let host = FirstClickHostingView(rootView: RootView(model: model))
        host.sizingOptions = [.minSize]
        let size = NSSize(width: Self.baseSize.width * CGFloat(model.settings.scale), height: Self.baseSize.height)
        let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: size), title: "Nora", content: host)
        if !panel.setFrameUsingName("NoraGlassPanel") { place(panel) }
        panel.setFrameAutosaveName("NoraGlassPanel")
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let width = min(panel.frame.width, screen.width - 48)
        let height = min(panel.frame.height, screen.height - 48)
        panel.setFrame(NSRect(x: screen.midX - width / 2, y: screen.midY - height / 2,
                              width: width, height: height), display: true)
    }

    private func resizePanel(for scale: Double) {
        guard let panel, let screen = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.width = min(Self.baseSize.width * CGFloat(scale), screen.width - 24)
        frame.size.height = min(max(frame.height, Self.baseSize.height), screen.height - 24)
        frame.origin.x = max(screen.minX + 12, min(frame.origin.x, screen.maxX - frame.width - 12))
        frame.origin.y = max(screen.minY + 12, top - frame.height)
        panel.setFrame(frame, display: true)
    }

    private func showTransparency() {
        guard let model else { return }
        if transparencyPanel == nil {
            let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 760), title: "What Nora is doing",
                                     content: FirstClickHostingView(rootView: TransparencyView(model: model)), utility: true)
            if !panel.setFrameUsingName("NoraActivityPanel") { panel.center() }
            panel.setFrameAutosaveName("NoraActivityPanel")
            transparencyPanel = panel
        }
        model.refreshHistory()
        transparencyPanel?.orderFrontRegardless()
    }

    private func showSettings() {
        guard let model else { return }
        if settingsPanel == nil {
            let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 760), title: "Nora Settings",
                                     content: FirstClickHostingView(rootView: SettingsView(model: model)), utility: true)
            if !panel.setFrameUsingName("NoraSettingsPanel") { panel.center() }
            panel.setFrameAutosaveName("NoraSettingsPanel")
            settingsPanel = panel
        }
        settingsPanel?.orderFrontRegardless()
    }

    /// Brings Nora forward with keyboard focus on the first tile, without activating the app.
    private func summon() {
        guard let panel, let model else { return }
        panel.makeKeyAndOrderFront(nil)
        model.requestedFocus = model.interaction.pendingConfirmation != nil ? .confirmCancel : .tile(TileCatalog.home[0].id)
    }

    // MARK: - Menus and keys

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Nora")
        appMenu.addItem(item("Settings…", #selector(openSettingsAction), ","))
        appMenu.addItem(item("What Nora Is Doing", #selector(openTransparencyAction), "t"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Nora", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Text fields rely on these key equivalents for copy and paste, even in an app with no visible menu bar.
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap.fill", accessibilityDescription: "Nora")
        let menu = NSMenu()
        menu.addItem(item("Show Nora (Option-Space)", #selector(summonAction), ""))
        menu.addItem(item("What Nora Is Doing", #selector(openTransparencyAction), ""))
        menu.addItem(item("Settings…", #selector(openSettingsAction), ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Nora", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettingsAction() { showSettings() }
    @objc private func openTransparencyAction() { showTransparency() }
    @objc private func summonAction() { summon() }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let model = self.model, let panel = self.panel, event.window === panel else { return event }
            let used = model.handleKey(characters: event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode,
                                       modifiers: event.modifierFlags, editingText: panel.firstResponder is NSTextView)
            return used ? nil : event
        }
    }
}
