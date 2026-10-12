import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private lazy var diagnosticsWindowController = DiagnosticsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        statusItemController = StatusItemController(
            onShowDiagnostics: { [weak self] in self?.diagnosticsWindowController.show() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    /// Opening CopyPal again (Finder, Spotlight, `open`) shows the diagnostics window,
    /// so the app stays reachable when the menu bar hides its icon (e.g. behind the notch).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        diagnosticsWindowController.show()
        return false
    }
}
