import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private lazy var diagnosticsWindowController = DiagnosticsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(
            onShowDiagnostics: { [weak self] in self?.diagnosticsWindowController.show() },
            onQuit: { NSApp.terminate(nil) }
        )
    }
}
