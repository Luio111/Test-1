/// Modifier keys of a keyboard event, independent of AppKit/CoreGraphics.
public struct KeyModifiers: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)
    public static let capsLock = KeyModifiers(rawValue: 1 << 5)

    /// ⌘ without ⇧, ⌥ or ⌃. Caps Lock and fn are ignored.
    public var isExactlyCommand: Bool {
        contains(.command) && isDisjoint(with: [.shift, .option, .control])
    }

    /// Order used in macOS menus: ⌃⌥⇧⌘.
    public var symbolsInMenuOrder: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    /// Short form for logs, e.g. "⌘⇧".
    public var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        if contains(.function) { result += "fn" }
        if contains(.capsLock) { result += "⇪" }
        return result
    }
}
