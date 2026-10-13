import AppKit
import Observation
import CopyPalCore
import CopyPalSystem

/// Drives the screenshot feature (ROADMAP M11): the hot key, the Screen Recording
/// permission gate and the overlay session. Observable for the settings page (hot
/// key availability, permission state).
@MainActor
@Observable
final class ScreenshotController {
    /// An overlay session is running.
    private(set) var isActive = false
    /// The permission window is open.
    private(set) var isShowingPermissionHint = false
    private(set) var permissionState: PermissionState = ScreenCapturePermission.state
    /// The system prompt was shown once; from then on only System Settings can help.
    private(set) var permissionAsked = AppSettings.screenshotPermissionAsked
    /// False when another app owns the shortcut (Carbon refused the registration).
    private(set) var hotKeyAvailable = true

    @ObservationIgnored private unowned let app: AppController
    @ObservationIgnored private var permissionWindow: ScreenshotPermissionWindowController?
    /// A start that waits for the permission window to report the grant.
    @ObservationIgnored private var startPending = false

    init(app: AppController) {
        self.app = app
    }

    /// Screen Recording worked once and is gone now: a warning in the menu bar.
    var permissionRevoked: Bool {
        AppSettings.screenshotEnabled && AppSettings.screenCaptureWasGranted && permissionState == .denied
    }

    // MARK: Hot key and menu

    /// ⌘⇧A: starts a session, or cancels the running one.
    func toggle() {
        if isActive {
            cancel()
        } else {
            start()
        }
    }

    /// Starts a session when the permission is there, else shows the permission window.
    func start() {
        guard AppSettings.screenshotEnabled, !isActive else { return }
        if app.popup.isVisible {
            app.popup.close(retracting: false)
        }
        refreshPermission()
        guard permissionState == .granted else {
            startPending = true
            showPermissionWindow()
            return
        }
        beginSession()
    }

    /// Ends the session without a capture (Esc, the hot key again, sleep, a screen change).
    func cancel() {
        guard isActive else { return }
        endSession()
    }

    func setHotKeyAvailable(_ available: Bool) {
        if hotKeyAvailable != available {
            hotKeyAvailable = available
        }
    }

    // MARK: Permission

    func refreshPermission() {
        let state = ScreenCapturePermission.state
        if state != permissionState {
            permissionState = state
            app.attentionDidChange()
        }
    }

    /// The system prompt (once per app identity), only ever from a button.
    func requestPermission() {
        AppSettings.screenshotPermissionAsked = true
        permissionAsked = true
        ScreenCapturePermission.request()
        refreshPermission()
    }

    func openSystemSettings() {
        ScreenCapturePermission.openSystemSettings()
    }

    func showPermissionWindow() {
        let window = permissionWindow ?? ScreenshotPermissionWindowController(controller: self)
        permissionWindow = window
        isShowingPermissionHint = true
        window.show()
    }

    /// Relaunches CopyPal: macOS applies a Screen Recording grant to new processes only.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    /// Called by the permission window.
    func permissionWindowDidClose() {
        isShowingPermissionHint = false
        refreshPermission()
    }

    /// Called by the permission window once ScreenCaptureKit confirmed the grant.
    func permissionWindowDidVerify() {
        refreshPermission()
        guard startPending else { return }
        startPending = false
        if permissionState == .granted, AppSettings.screenshotEnabled {
            beginSession()
        }
    }

    // MARK: Session

    private func beginSession() {
        startPending = false
        // The overlay follows in the next step of M11; until then the gate is in place.
        Log.app.info("Bildschirmfoto: Freigabe vorhanden, Aufnahme-Overlay folgt")
    }

    private func endSession() {
        isActive = false
    }
}
