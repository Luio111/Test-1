/// What a key press inside the popup means (ROADMAP §1.8).
public enum PopupKeyAction: Sendable, Equatable {
    /// Paste entry `index` (1-based); `plainText` when ⇧ is held.
    case select(index: Int, plainText: Bool)
    /// Paste the selected entry.
    case confirm(plainText: Bool)
    case moveUp
    case moveDown
    /// Close the popup.
    case cancel
    /// Esc with search text: clear the search first.
    case clearQuery
    case insertText(String)
    case deleteBackward
    /// ⇥: switch between history and favorites.
    case switchList
    /// ⌘P: add to / remove from favorites.
    case togglePin
    /// ⌘⌫: delete the selected entry.
    case deleteItem
    /// →: show the selected entry in full instead of the list.
    case showPreview
    /// ←: back from the preview to the list.
    case hidePreview
}

/// Maps physical keys to popup actions. Digits are matched by key code, not by the
/// character they produce, so ⇧+digit works on QWERTZ and AZERTY too.
public enum PopupKeyMap {
    public static let maxIndex = 8

    /// Number row 1–8 (same physical keys on ANSI, ISO and JIS keyboards).
    static let numberRow: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8]
    /// Keypad 1–8.
    static let keypad: [UInt16: Int] = [83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8]

    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let tab: UInt16 = 48
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117

    /// - Parameters:
    ///   - characters: the text the key produces with its modifiers (`NSEvent.characters`).
    ///   - baseCharacters: the text without modifiers (`charactersIgnoringModifiers`), for ⌘ shortcuts.
    ///   - queryIsEmpty: digits paste only while nothing has been typed.
    public static func action(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        characters: String? = nil,
        baseCharacters: String? = nil,
        queryIsEmpty: Bool = true
    ) -> PopupKeyAction? {
        let plainText = modifiers.contains(.shift)
        let command = modifiers.contains(.command)

        if let index = numberRow[keyCode] ?? keypad[keyCode] {
            // With ⌘ (e.g. still held from ⌘V) or an empty search: paste. Otherwise the
            // digit is part of the search text.
            if command || queryIsEmpty {
                return .select(index: index, plainText: plainText)
            }
            return insertion(characters, modifiers: modifiers)
        }

        switch keyCode {
        case escape:
            return queryIsEmpty ? .cancel : .clearQuery
        case returnKey, keypadEnter:
            return .confirm(plainText: plainText)
        case upArrow:
            return .moveUp
        case downArrow:
            return .moveDown
        case rightArrow:
            return .showPreview
        case leftArrow:
            return .hidePreview
        case tab:
            return .switchList
        case delete, forwardDelete:
            return command ? .deleteItem : (queryIsEmpty ? nil : .deleteBackward)
        default:
            break
        }

        if command {
            return baseCharacters?.lowercased() == "p" ? .togglePin : nil
        }
        return insertion(characters, modifiers: modifiers)
    }

    /// Printable text (⌥ allowed, e.g. "@" on German keyboards; ⌃ not).
    private static func insertion(_ characters: String?, modifiers: KeyModifiers) -> PopupKeyAction? {
        guard !modifiers.contains(.control), let characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ isPrintable($0) }) else {
            return nil
        }
        return .insertText(characters)
    }

    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        // Function keys arrive as private-use characters (U+F700…U+F8FF).
        if (0xF700...0xF8FF).contains(scalar.value) { return false }
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator:
            return false
        default:
            return true
        }
    }
}
