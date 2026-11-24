import AppKit
import SwiftUI

extension NSWindow.CollectionBehavior {
    /// A short-lived overlay at the notch, shown wherever the user is right now: it
    /// moves to the active Space when it is ordered in (so a panel created at launch
    /// and first shown over another app's full-screen Space lands on that Space, not
    /// on the desktop behind it), may join other apps' full-screen Spaces, and stays
    /// out of Mission Control, Exposé and the window cycle.
    static let notchOverlay: NSWindow.CollectionBehavior = [
        .moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications, .stationary, .ignoresCycle,
    ]
}

extension NSWindow.Level {
    /// The popup, its retract animation and the toast at the notch. Above the menu bar
    /// and its status items, and above the menu bar that slides in over a full-screen
    /// app when the pointer reaches the top edge: at `.statusBar` either one could end
    /// up over "Verlauf | Favoriten" beside the notch and take the click.
    static var aboveMenuBar: NSWindow.Level { .screenSaver }
}

extension NSWindow {
    /// Asks screen sharing to leave the window out, as set under Datenschutz. Applied
    /// each time a notch window appears, so a changed setting counts at once.
    func applyScreenSharingPreference() {
        sharingType = AppSettings.hideFromScreenSharing ? .none : .readOnly
    }

    /// Orders the window in on the Space the user sees. Seen with the popup: first shown
    /// over another app's full-screen Space, a panel stayed on the desktop behind it;
    /// ordering it in again moves it to the active Space. False when it is still elsewhere.
    @discardableResult
    func orderFrontOnActiveSpace() -> Bool {
        orderFrontRegardless()
        if !isOnActiveSpace {
            orderOut(nil)
            orderFrontRegardless()
        }
        return isOnActiveSpace
    }
}

/// Takes the first click. The popup never activates CopyPal (the app being pasted
/// into stays in front), so for macOS every click is the first click into an inactive
/// app – which NSHostingView ignores by default: buttons and rows would not react.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

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

/// Shared setup: above the menu bar, transparent, always dark (the notch is black).
/// No window shadow: it would keep the outline of the first frame while the shape
/// animates; the view draws its own.
@MainActor
private func configureForNotch(_ panel: NSPanel) {
    panel.isFloatingPanel = true
    panel.level = .aboveMenuBar
    panel.collectionBehavior = .notchOverlay
    panel.becomesKeyOnlyIfNeeded = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = .none
    panel.appearance = NSAppearance(named: .darkAqua)
}
