import Foundation

/// How copies from the iPhone (Universal Clipboard) are handled (ROADMAP D3).
public enum RemoteClipboardMode: String, Sendable, Codable, CaseIterable {
    /// Not recorded.
    case ignore
    /// Recorded from the types only; the content is read when the user picks the
    /// entry, so macOS asks "Paste from iPhone" only for a deliberate action.
    case onDemand
    /// Read right away like a local copy (macOS may show its paste prompt).
    case readImmediately
}

public struct PrivacySettings: Sendable, Equatable {
    public var ignoredBundleIDs: Set<String>
    public var pausedUntil: Date?
    public var remoteMode: RemoteClipboardMode

    public init(
        ignoredBundleIDs: Set<String> = DefaultIgnoreList.bundleIDs,
        pausedUntil: Date? = nil,
        remoteMode: RemoteClipboardMode = .onDemand
    ) {
        self.ignoredBundleIDs = ignoredBundleIDs
        self.pausedUntil = pausedUntil
        self.remoteMode = remoteMode
    }

    public func isPaused(at now: Date) -> Bool {
        guard let pausedUntil else { return false }
        return now < pausedUntil
    }
}

/// What to do with a pasteboard change, decided before any content is read.
public enum CaptureDecision: Sendable, Equatable {
    case skip(CaptureSkipReason)
    /// Record an iPhone copy without reading it (`RemoteClipboardMode.onDemand`).
    case recordRemotePlaceholder
    case read(origin: ClipOrigin)
}

public enum PrivacyFilter {
    /// Pause and ignore list first, then the pasteboard markers, then iPhone handling.
    public static func decide(
        types: [String],
        sourceBundleID: String?,
        settings: PrivacySettings,
        now: Date
    ) -> CaptureDecision {
        if settings.isPaused(at: now) { return .skip(.paused) }
        if let sourceBundleID, settings.ignoredBundleIDs.contains(sourceBundleID) { return .skip(.ignoredApp) }
        switch PasteboardMarkers.decide(types: types) {
        case let .skip(reason):
            return .skip(reason)
        case .read:
            return .read(origin: .local)
        case .remote:
            switch settings.remoteMode {
            case .ignore: return .skip(.remoteIgnored)
            case .onDemand: return .recordRemotePlaceholder
            case .readImmediately: return .read(origin: .remoteDevice)
            }
        }
    }
}

/// Apps whose copies are never recorded unless the user removes them from the list:
/// password managers, Keychain Access, the Passwords app and banking apps. Bundle IDs
/// can be checked with `osascript -e 'id of app "Name"'`.
public enum DefaultIgnoreList {
    public static let entries: [(bundleID: String, name: String)] = [
        ("com.1password.1password", "1Password"),
        ("com.agilebits.onepassword7", "1Password 7"),
        ("com.bitwarden.desktop", "Bitwarden"),
        ("com.apple.keychainaccess", "Schlüsselbundverwaltung"),
        ("com.apple.Passwords", "Passwörter"),
        ("org.keepassxc.keepassxc", "KeePassXC"),
        ("com.lastpass.LastPass", "LastPass"),
        ("in.sinew.Enpass-Desktop", "Enpass"),
        ("com.moneymoney-app.retail", "MoneyMoney"),
    ]

    public static var bundleIDs: Set<String> {
        Set(entries.map(\.bundleID))
    }
}
