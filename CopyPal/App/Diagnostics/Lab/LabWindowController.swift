#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class LabWindowController: NSObject, NSWindowDelegate {
    private let model: LabModel
    private var window: NSWindow?

    init(app: AppController) {
        model = LabModel(app: app)
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        model.start()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: LabView(model: model)))
        window.title = String(localized: "Labor")
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.Colors.windowBackground
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 660, height: 760))
        window.center()
        window.delegate = self
        return window
    }
}
#endif
