import AppKit

/// CopyPal's windows (settings, history, diagnostics …) activate CopyPal. Closing the
/// last of them gives the focus back to the app that was in front before, so typing
/// goes on there instead of into an app without windows.
@MainActor
enum FocusReturn {
    private static var previous: NSRunningApplication?

    /// Before a CopyPal window activates CopyPal.
    static func remember() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        previous = front
    }

    /// From `windowWillClose`: hands the focus back when no other CopyPal window stays.
    static func windowWillClose(_ window: NSWindow?) {
        guard !AppController.isSelfTest, NSApp.isActive else { return }
        let otherWindowOpen = NSApp.windows.contains { other in
            other !== window && other.isVisible && !(other is NSPanel) && other.styleMask.contains(.titled)
        }
        guard !otherWindowOpen else { return }
        let app = previous
        previous = nil
        if let app, !app.isTerminated {
            _ = app.activate()
        }
    }
}
