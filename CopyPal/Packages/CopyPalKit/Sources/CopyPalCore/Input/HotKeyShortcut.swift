/// A key combination for the fallback hotkey that opens the popup (ROADMAP D5).
public struct HotKeyShortcut: Sendable, Equatable, Codable {
    /// Physical key (virtual key code).
    public var keyCode: UInt16
    public var modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥V (physical V key).
    public static let standard = HotKeyShortcut(keyCode: 9, modifiers: [.control, .option])

    /// ⌘⇧A for the screenshot (M11, ROADMAP D14): key code 0 is "A" on ANSI, ISO and
    /// QWERTZ layouts alike.
    public static let screenshotStandard = HotKeyShortcut(keyCode: 0, modifiers: [.command, .shift])

    /// Needs at least one of ⌘, ⌥, ⌃ so ordinary typing is never captured, and must
    /// not be plain ⌘V.
    public var isValid: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control])
            && !(keyCode == 9 && modifiers.isExactlyCommand)
    }
}
