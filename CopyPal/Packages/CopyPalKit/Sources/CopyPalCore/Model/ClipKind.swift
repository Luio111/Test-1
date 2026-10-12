/// What a history entry mainly contains. Decides the row icon and preview.
public enum ClipKind: String, Sendable, Codable, CaseIterable {
    case text
    case richText
    case link
    case color
    case image
    case files
    case other
}

/// Where a copy came from.
public enum ClipOrigin: String, Sendable, Codable {
    case local
    /// Universal Clipboard: copied on the iPhone (or another Apple device).
    case remoteDevice
}

/// Kind of sensitive content (ROADMAP M5). Sensitive entries are masked, not
/// searchable, expire quickly and are pasted "on this Mac only".
public enum Sensitivity: String, Sendable, Codable, CaseIterable {
    case iban
    case card
    /// API keys, tokens, private keys.
    case secret
    case oneTimeCode
}
