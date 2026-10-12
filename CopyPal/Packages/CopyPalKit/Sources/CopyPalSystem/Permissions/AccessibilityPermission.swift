#if os(macOS)
import AppKit
import ApplicationServices
import CopyPalCore

/// Accessibility (Bedienungshilfen) is required for the active event tap that
/// intercepts ⌘V and for posting the synthesized paste.
public enum AccessibilityPermission {
    public static var state: PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Shows the system prompt if the app is not trusted yet. macOS only shows it
    /// once per app identity; afterwards use `openSystemSettings()`.
    @discardableResult
    public static func request() -> PermissionState {
        // Literal key instead of `kAXTrustedCheckOptionPrompt`: that global is a
        // mutable C var and not concurrency-safe under strict checking.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
    }

    @MainActor
    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
#endif
