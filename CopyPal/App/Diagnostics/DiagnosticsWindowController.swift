import AppKit
import SwiftUI

/// Hosts `DiagnosticsView` in a plain window with a transparent title bar.
@MainActor
final class DiagnosticsWindowController: NSObject, NSWindowDelegate {
    private let model = DiagnosticsModel()
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        model.refresh()
        model.startMonitoring()

        // Accessory apps are not active by default; without this the window opens
        // behind the frontmost app.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopMonitoring()
    }

    /// Coming back from System Settings: re-read every row, not only the live ones.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: DiagnosticsView(model: model)))
        window.title = String(localized: "Diagnose")
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.Colors.windowBackground
        window.isReleasedWhenClosed = false
        window.setContentSize(Theme.Layout.windowSize)
        window.center()
        window.delegate = self
        return window
    }
}
