import AppKit

/// AppKit entry point: a menu bar app without Dock icon or main window
/// (`LSUIElement`, see Config/Base.xcconfig).
@main
enum CopyPalMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // `NSApplication.delegate` is weak; keep the delegate alive for the app's lifetime.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
