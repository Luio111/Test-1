/// What a key press inside the popup means.
public enum PopupKeyAction: Sendable, Equatable {
    /// Paste entry `index` (1-based); `plainText` when ⇧ is held.
    case select(index: Int, plainText: Bool)
    case confirm(plainText: Bool)
    case moveUp
    case moveDown
    case cancel
}

/// Maps physical keys to popup actions. Digits are matched by key code, not by the
/// character they produce, so ⇧+digit works on QWERTZ and AZERTY too (ROADMAP §1.8).
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

    public static func action(keyCode: UInt16, modifiers: KeyModifiers) -> PopupKeyAction? {
        let plainText = modifiers.contains(.shift)
        if let index = numberRow[keyCode] ?? keypad[keyCode] {
            return .select(index: index, plainText: plainText)
        }
        switch keyCode {
        case escape: return .cancel
        case returnKey, keypadEnter: return .confirm(plainText: plainText)
        case upArrow: return .moveUp
        case downArrow: return .moveDown
        default: return nil
        }
    }
}
