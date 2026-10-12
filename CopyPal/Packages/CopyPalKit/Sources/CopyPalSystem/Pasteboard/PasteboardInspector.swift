#if os(macOS)
import AppKit
import CopyPalCore

/// Read-only checks of the pasteboard for diagnostics. Reads metadata (change count
/// and type identifiers) only, never contents.
public enum PasteboardInspector {
    /// The per-app pasteboard privacy setting introduced in macOS 15.4.
    public static func accessStatus(of pasteboard: NSPasteboard = .general) -> PasteboardAccessStatus {
        // `accessBehavior` only exists in the macOS 15.4 SDK (Xcode 16.3, Swift 6.1) and later.
        #if compiler(>=6.1)
        if #available(macOS 15.4, *) {
            let behavior = pasteboard.accessBehavior
            switch behavior {
            case .default: return .systemDefault
            case .ask: return .ask
            case .alwaysAllow: return .alwaysAllow
            case .alwaysDeny: return .alwaysDeny
            @unknown default: return .unknown(rawValue: behavior.rawValue)
            }
        }
        #endif
        return .unavailable
    }

    /// Reads `changeCount` and `types` once and measures how long that takes.
    /// Run it from a user action: on systems that ask before programmatic reads,
    /// this is exactly the access that would trigger the prompt.
    public static func probe(_ pasteboard: NSPasteboard = .general) -> PasteboardProbe {
        let clock = ContinuousClock()
        let start = clock.now
        let changeCount = pasteboard.changeCount
        let types = pasteboard.types?.map(\.rawValue) ?? []
        return PasteboardProbe(changeCount: changeCount, types: types, duration: clock.now - start)
    }
}
#endif
