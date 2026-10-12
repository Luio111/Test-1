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
    /// This macOS version has no per-app pasteboard setting (before 15.4).
    case unavailable
    /// macOS has the setting, but the app was built with an SDK older than 15.4
    /// (Xcode < 16.3) and cannot read it.
    case notInBuildSDK
    case systemDefault
    case ask
    case alwaysAllow
    case alwaysDeny
    case unknown(rawValue: Int)

    /// `true` when background reads could be blocked or interrupted by a system prompt.
    public var mayInterruptCapture: Bool {
        switch self {
        case .ask, .alwaysDeny, .systemDefault, .notInBuildSDK, .unknown: true
        case .unavailable, .alwaysAllow: false
        }
    }
}

/// Problems the diagnostics window and report point out. Typed so the UI has to
/// handle every case (exhaustive switch) and stays in sync with the report.
public enum DiagnosticsWarning: Sendable, Hashable, CaseIterable {
    case unstableSigning
    case accessibilityDenied
    case pasteboardMayAsk
    case pasteboardDenied
    case pasteboardStatusUnknown

    public static func warnings(for snapshot: DiagnosticsSnapshot) -> [DiagnosticsWarning] {
        var result: [DiagnosticsWarning] = []
        if !snapshot.signing.isStable { result.append(.unstableSigning) }
        if snapshot.accessibility == .denied { result.append(.accessibilityDenied) }
        switch snapshot.pasteboardAccess {
        case .ask, .systemDefault: result.append(.pasteboardMayAsk)
        case .alwaysDeny: result.append(.pasteboardDenied)
        case .notInBuildSDK, .unknown: result.append(.pasteboardStatusUnknown)
        case .unavailable, .alwaysAllow: break
        }
        return result
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

    public var milliseconds: Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }
}

public struct DiagnosticsSnapshot: Sendable, Equatable {
    public var appVersion: String
    public var buildNumber: String
    public var bundleIdentifier: String
    /// Xcode and SDK the app was built with, e.g. "Xcode 16.4 · macosx15.5".
    public var buildEnvironment: String
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
        buildEnvironment: String,
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
        self.buildEnvironment = buildEnvironment
        self.osVersion = osVersion
        self.signing = signing
        self.accessibility = accessibility
        self.pasteboardAccess = pasteboardAccess
        self.pasteboardProbe = pasteboardProbe
        self.createdAt = createdAt
    }
}
