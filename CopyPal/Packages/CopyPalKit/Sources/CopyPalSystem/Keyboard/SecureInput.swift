#if os(macOS)
import AppKit
import Carbon

/// "Secure Event Input" (password fields, Terminal's secure keyboard entry) hides
/// all key events from event taps. Then ⌘V works normally, but holding does nothing.
public enum SecureInput {
    public struct Status: Sendable, Equatable {
        public var isEnabled: Bool
        /// Name of the app that turned it on, when macOS reports it.
        public var appName: String?

        public static let off = Status(isEnabled: false, appName: nil)
    }

    public static func current() -> Status {
        // `== true` works whether the Carbon `Boolean` is imported as Bool or DarwinBoolean.
        let isEnabled = IsSecureEventInputEnabled() == true
        guard isEnabled else { return Status(isEnabled: false, appName: nil) }
        return Status(isEnabled: true, appName: owningAppName())
    }

    private static func owningAppName() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value,
              pid > 0 else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
#endif
