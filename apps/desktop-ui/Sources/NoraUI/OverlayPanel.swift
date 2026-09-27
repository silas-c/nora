import AppKit
import SwiftUI

/// A panel that never activates Nora. The app the person is using stays frontmost, so keyboard actions such as
/// zoom reach that app rather than Nora. The main panel floats; Settings and the activity window are ordinary
/// windows that other apps cover when the person clicks away.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect, title: String, content: NSView, utility: Bool = false) {
        var style: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]
        if utility { style.insert(.utilityWindow) }
        super.init(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        self.title = title
        titleVisibility = utility ? .visible : .hidden
        titlebarAppearsTransparent = !utility
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        isFloatingPanel = !utility
        level = utility ? .normal : .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = utility ? [.moveToActiveSpace, .fullScreenAuxiliary] : [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentRect.size))
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        content.frame = backdrop.bounds
        content.autoresizingMask = [.width, .height]
        backdrop.addSubview(content)
        contentView = backdrop
    }

    override var canBecomeKey: Bool { true }
    /// A main window would make Nora the app in front. Keyboard focus is enough.
    override var canBecomeMain: Bool { false }
}

/// Every click counts: the first click on an inactive panel acts instead of only focusing the window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
