#if os(macOS)
import Carbon
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

    /// How a shortcut is written in menus, e.g. "⌃⌥V", in the current layout.
    public static func displayString(for shortcut: HotKeyShortcut) -> String {
        shortcut.modifiers.symbolsInMenuOrder + keyName(for: shortcut.keyCode)
    }

    /// Printable name of a physical key in the current layout ("V", "Space", "F5" …).
    public static func keyName(for keyCode: UInt16) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let layoutData = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue()
            if let bytes = CFDataGetBytePtr(layoutData) {
                let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
                if let character = character(for: keyCode, layout: layout, modifiers: 0), !character.isEmpty {
                    return character.uppercased()
                }
            }
        }
        return "#\(keyCode)"
    }

    private static let specialKeyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋", UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓", UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]

    private static func character(for keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>) -> String? {
        character(for: keyCode, layout: layout, modifiers: UInt32((cmdKey >> 8) & 0xFF))?.lowercased()
    }

    private static func character(for keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>, modifiers: UInt32) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifiers,
            UInt32(LMGetKbdType()),
            OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == 0, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
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
