import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private lazy var diagnosticsWindowController = DiagnosticsWindowController()
    private lazy var input = InputCoordinator()

    #if DEBUG
    private lazy var labWindowController = LabWindowController(input: input)
    private var selfTest: SelfTestRunner?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        NSApp.mainMenu = MainMenu.make()
        input.start()

        var showLab: (() -> Void)?
        #if DEBUG
        showLab = { [weak self] in self?.labWindowController.show() }
        #endif

        statusItemController = StatusItemController(
            onShowDiagnostics: { [weak self] in self?.diagnosticsWindowController.show() },
            onShowLab: showLab,
            onQuit: { NSApp.terminate(nil) }
        )

        #if DEBUG
        if SelfTestRunner.isRequested {
            let runner = SelfTestRunner(input: input)
            selfTest = runner
            runner.run()
        }
        #endif
    }

    /// Opening CopyPal again (Finder, Spotlight, `open`) shows the diagnostics window,
    /// so the app stays reachable when the menu bar hides its icon (e.g. behind the notch).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        diagnosticsWindowController.show()
        return false
    }
}
