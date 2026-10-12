import AppKit

/// Borderless, non-activating panel: it can take keyboard input while the app the
/// user is working in stays active, so focus returns there when it closes.
final class PopupPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureForNotch(self)
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The popup hangs from the top edge, over the menu bar and around the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Shows the popup shrinking back into the notch after it closed. Never takes
/// focus or clicks, so typing and the paste go straight to the app underneath.
final class NotchRetractPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureForNotch(self)
        ignoresMouseEvents = true
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Shared setup: above the menu bar on every Space, transparent, always dark (the
/// notch is black). No window shadow: it would keep the outline of the first frame
/// while the shape animates; the view draws its own.
@MainActor
private func configureForNotch(_ panel: NSPanel) {
    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.becomesKeyOnlyIfNeeded = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = .none
    panel.appearance = NSAppearance(named: .darkAqua)
}
