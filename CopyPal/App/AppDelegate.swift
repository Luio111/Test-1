import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var app = AppController()

    #if DEBUG
    private var selfTest: SelfTestRunner?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.start()

        #if DEBUG
        if SelfTestRunner.isRequested {
            let runner = SelfTestRunner(app: app)
            selfTest = runner
            runner.run()
        }
        #endif
    }

    /// Opening CopyPal again (Finder, Spotlight, `open`) shows the settings (or the
    /// onboarding), so the app stays reachable when the menu bar hides its icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        app.reopen()
        return false
    }
}
