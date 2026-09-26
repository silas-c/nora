import AppKit
import SwiftUI

/// A floating panel that never activates Nora. The app the person is using stays frontmost,
/// so keyboard actions such as zoom reach that app rather than Nora.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect, title: String, content: NSView, utility: Bool = false) {
        var style: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]
        if utility { style.insert(.utilityWindow) }
        super.init(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        self.title = title
        titleVisibility = utility ? .visible : .hidden
        titlebarAppearsTransparent = !utility
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    /// A main window would make Nora the app in front. Keyboard focus is enough.
    override var canBecomeMain: Bool { false }
}

/// Every click counts: the first click on an inactive panel acts instead of only focusing the window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
