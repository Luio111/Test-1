#if os(macOS)
import CoreGraphics

/// Posts keyboard events on behalf of CopyPal. Every event carries `marker` in
/// `eventSourceUserData`, so the event tap recognizes and passes its own events.
public enum PasteSynthesizer {
    /// "CopyPal" in ASCII.
    public static let marker: Int64 = 0x43_6F_70_79_50_61_6C

    public static func isOwn(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// Posts ⌘V (down + up). The private event source keeps physically held keys
    /// (e.g. ⇧) out, so the target app sees exactly ⌘V.
    public static func postPaste(keyCode: UInt16) {
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: isDown) else {
                continue
            }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Re-posts a swallowed event unchanged (apart from the marker).
    public static func replay(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: marker)
        copy.post(tap: .cghidEventTap)
    }
}
#endif
