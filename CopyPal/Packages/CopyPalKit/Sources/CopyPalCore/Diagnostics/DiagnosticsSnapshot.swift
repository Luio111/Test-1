import Foundation

/// How the running app is code-signed. Only `.developer` keeps macOS privacy
/// grants (Accessibility) stable across rebuilds.
public enum SigningStatus: Sendable, Equatable {
    case developer(teamID: String, certificate: String?)
    case adHoc
    case unsigned
    case unknown(String)

    public var isStable: Bool {
        if case .developer = self { return true }
        return false
    }
}

public enum PermissionState: Sendable, Equatable {
    case granted
    case denied
}

/// Mirrors `NSPasteboard.AccessBehavior` (macOS 15.4+) without depending on AppKit.
public enum PasteboardAccessStatus: Sendable, Equatable {
    /// The API does not exist on this macOS version (or the SDK used to build is too old).
    case unavailable
    case systemDefault
    case ask
    case alwaysAllow
    case alwaysDeny
    case unknown(rawValue: Int)

    /// `true` when background reads could be blocked or interrupted by a system prompt.
    public var mayInterruptCapture: Bool {
        switch self {
        case .ask, .alwaysDeny, .systemDefault, .unknown: true
        case .unavailable, .alwaysAllow: false
        }
    }
}

/// Result of reading the pasteboard metadata once. Contains type identifiers only,
/// never clipboard contents.
public struct PasteboardProbe: Sendable, Equatable {
    public var changeCount: Int
    public var types: [String]
    public var duration: Duration

    public init(changeCount: Int, types: [String], duration: Duration) {
        self.changeCount = changeCount
        self.types = types
        self.duration = duration
    }
}

public struct DiagnosticsSnapshot: Sendable, Equatable {
    public var appVersion: String
    public var buildNumber: String
    public var bundleIdentifier: String
    public var osVersion: String
    public var signing: SigningStatus
    public var accessibility: PermissionState
    public var pasteboardAccess: PasteboardAccessStatus
    public var pasteboardProbe: PasteboardProbe?
    public var createdAt: Date

    public init(
        appVersion: String,
        buildNumber: String,
        bundleIdentifier: String,
        osVersion: String,
        signing: SigningStatus,
        accessibility: PermissionState,
        pasteboardAccess: PasteboardAccessStatus,
        pasteboardProbe: PasteboardProbe? = nil,
        createdAt: Date = Date()
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.bundleIdentifier = bundleIdentifier
        self.osVersion = osVersion
        self.signing = signing
        self.accessibility = accessibility
        self.pasteboardAccess = pasteboardAccess
        self.pasteboardProbe = pasteboardProbe
        self.createdAt = createdAt
    }
}
