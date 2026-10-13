#if os(macOS)
import AppKit
import CoreGraphics
import CopyPalCore

/// Screen Recording (Bildschirmaufnahme) is required for screenshots (ROADMAP M11).
/// Everything else – the window list, the Accessibility API – works without it.
public enum ScreenCapturePermission {
    public static var state: PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Shows the system prompt if the app has not asked yet (macOS shows it once per
    /// app identity) and returns the state as it is right now. A grant made in System
    /// Settings afterwards is picked up by `state`, sometimes only after a relaunch.
    @discardableResult
    public static func request() -> PermissionState {
        CGRequestScreenCaptureAccess() ? .granted : .denied
    }

    @MainActor
    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
#endif
