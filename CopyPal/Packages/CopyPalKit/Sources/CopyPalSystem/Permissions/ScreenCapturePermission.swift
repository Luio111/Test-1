#if os(macOS)
import AppKit
import CoreGraphics
import CopyPalCore

/// Screen Recording (Bildschirmaufnahme) is required for screenshots (ROADMAP M11).
/// Everything else – the window list, the Accessibility API – works without it.
public enum ScreenCapturePermission {
    /// What a real capture attempt says, beyond the preflight.
    public enum VerifiedState: Sendable, Equatable {
        case granted
        case denied
        /// System Settings show the permission, but this process does not have it yet.
        case needsRelaunch
        case failed(String)
    }

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

    /// Asks ScreenCaptureKit itself: the preflight can say yes while the process still
    /// runs without the permission (granted after launch), and vice versa after a reset.
    /// Shows the system prompt when the permission was never decided – call it only
    /// after `request()` or when the preflight says granted.
    public static func verify() async -> VerifiedState {
        let preflight = CGPreflightScreenCaptureAccess()
        do {
            try await ScreenCaptureEngine.checkPermission()
            return .granted
        } catch ScreenCaptureEngine.Failure.permissionDenied {
            return preflight ? .needsRelaunch : .denied
        } catch {
            return .failed(String(describing: error))
        }
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
