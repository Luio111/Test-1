#if os(macOS)
import Carbon.HIToolbox
import Foundation

/// Finds the physical key that produces "v" together with ⌘ in the current keyboard
/// layout. Uses ⌘ as modifier so layouts like "Dvorak – QWERTY ⌘" resolve to the
/// QWERTY position, exactly like the system does for shortcuts.
public enum KeyboardLayout {
    /// `kVK_ANSI_V`: the V key on QWERTY/QWERTZ/AZERTY.
    public static let fallbackPasteKeyCode = UInt16(kVK_ANSI_V)

    public struct Resolution: Sendable, Equatable {
        public var pasteKeyCode: UInt16
        public var layoutName: String
        /// False when the layout data could not be read and the fallback is used.
        public var resolved: Bool
    }

    public static func resolvePasteKey() -> Resolution {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return Resolution(pasteKeyCode: fallbackPasteKeyCode, layoutName: "?", resolved: false)
        }
        let name = stringProperty(source, kTISPropertyLocalizedName) ?? "?"
        guard let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return Resolution(pasteKeyCode: fallbackPasteKeyCode, layoutName: name, resolved: false)
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else {
            return Resolution(pasteKeyCode: fallbackPasteKeyCode, layoutName: name, resolved: false)
        }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        // Prefer the usual position, then scan all key codes.
        let candidates = [fallbackPasteKeyCode] + Array(UInt16(0)..<128)
        for keyCode in candidates where character(for: keyCode, layout: layout) == "v" {
            return Resolution(pasteKeyCode: keyCode, layoutName: name, resolved: true)
        }
        return Resolution(pasteKeyCode: fallbackPasteKeyCode, layoutName: name, resolved: false)
    }

    private static func character(for keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let commandModifier = UInt32((cmdKey >> 8) & 0xFF)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            commandModifier,
            UInt32(LMGetKbdType()),
            OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == 0, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).lowercased()
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    /// Distributed notification posted when the user switches the input source.
    public static var selectionChangedNotification: Notification.Name {
        Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
    }
}
#endif
