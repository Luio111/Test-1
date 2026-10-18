import Foundation
import CopyPalCore
import CopyPalServices

/// User-adjustable values (UserDefaults). Every setter posts `didChange`, and the app
/// re-applies the settings at once (ROADMAP M7: no restart needed).
enum AppSettings {
    static let didChange = Notification.Name("CopyPal.settingsDidChange")

    private enum Key {
        static let holdThreshold = "holdThreshold"
        static let pasteDelayMilliseconds = "pasteDelayMilliseconds"
        static let holdGestureEnabled = "holdGestureEnabled"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let hotKey = "hotKey"
        static let historyLimit = "historyLimit"
        static let retentionDays = "retentionDays"
        static let sensitiveLifetime = "sensitiveLifetimeSeconds"
        static let detectOneTimeCodes = "detectOneTimeCodes"
        static let clearPasteboardAfterSensitive = "clearPasteboardAfterSensitive"
        static let remoteClipboardMode = "remoteClipboardMode"
        static let customIgnoredApps = "customIgnoredBundleIDs"
        static let removedDefaultIgnoredApps = "removedDefaultIgnoredBundleIDs"
        static let holdDisabledApps = "holdDisabledBundleIDs"
        static let pausedUntil = "pausedUntil"
        static let showCopyFeedback = "showCopyFeedback"
        static let animatePopup = "animatePopup"
        static let loadFavicons = "loadFavicons"
        static let cleanLinks = "cleanLinksOnPlainPaste"
        static let hideFromScreenSharing = "hideFromScreenSharing"
        static let recognizeTextInImages = "recognizeTextInImages"
        static let presentationUntil = "presentationUntil"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let screenshotEnabled = "screenshotEnabled"
        static let screenshotHotKey = "screenshotHotKey"
        static let screenshotScrollReversed = "screenshotScrollReversed"
        static let screenshotPermissionAsked = "screenshotPermissionAsked"
        static let screenCaptureWasGranted = "screenCaptureWasGranted"
    }

    /// Read by the Sparkle delegate off the main actor, hence public and plain.
    static let betaUpdatesKey = "betaUpdates"

    static let holdThresholdRange: ClosedRange<Double> = 0.15...0.6
    static let pasteDelayRange: ClosedRange<Double> = 0...150
    static let historyLimitOptions = [100, 250, 500, 1_000, 2_000]
    /// 0 = keep until the limit is reached.
    static let retentionDayOptions = [1, 7, 30, 90, 365, 0]
    static let sensitiveLifetimeOptions = [30, 60, 300, 900]

    /// The self-test uses its own, emptied defaults, so it never changes the user's settings.
    /// `UserDefaults` is thread-safe (documented), but not marked Sendable in the SDK.
    nonisolated(unsafe) private static let defaults: UserDefaults = {
        let suiteName = "CopyPal.SelfTest"
        if CommandLine.arguments.contains("--self-test"), let suite = UserDefaults(suiteName: suiteName) {
            suite.removePersistentDomain(forName: suiteName)
            return suite
        }
        return .standard
    }()

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.holdThreshold: 0.3,
            Key.pasteDelayMilliseconds: 30.0,
            Key.holdGestureEnabled: true,
            Key.hotKeyEnabled: true,
            Key.historyLimit: 500,
            Key.retentionDays: 30,
            Key.sensitiveLifetime: 60,
            Key.detectOneTimeCodes: true,
            Key.clearPasteboardAfterSensitive: false,
            Key.remoteClipboardMode: RemoteClipboardMode.onDemand.rawValue,
            Key.holdDisabledApps: HoldOffList.defaultBundleIDs,
            Key.showCopyFeedback: true,
            Key.animatePopup: true,
            Key.loadFavicons: false,
            Key.cleanLinks: true,
            Key.hideFromScreenSharing: true,
            Key.recognizeTextInImages: true,
            Key.hasCompletedOnboarding: false,
            Key.screenshotEnabled: true,
            Key.screenshotScrollReversed: false,
            Key.screenshotPermissionAsked: false,
            Key.screenCaptureWasGranted: false,
        ])
    }

    private static func set(_ value: Any?, for key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: Gesture

    /// Seconds ⌘V must be held before the popup opens (ROADMAP D2).
    static var holdThreshold: Double {
        get { defaults.double(forKey: Key.holdThreshold) }
        set { set(newValue.clamped(to: holdThresholdRange), for: Key.holdThreshold) }
    }

    /// Wait between closing the popup and posting ⌘V, so focus is back in the target app.
    static var pasteDelayMilliseconds: Double {
        get { defaults.double(forKey: Key.pasteDelayMilliseconds) }
        set { set(newValue.clamped(to: pasteDelayRange), for: Key.pasteDelayMilliseconds) }
    }

    /// Plan B (ROADMAP G1): off leaves ⌘V completely alone; the hotkey still works.
    static var holdGestureEnabled: Bool {
        get { defaults.bool(forKey: Key.holdGestureEnabled) }
        set { set(newValue, for: Key.holdGestureEnabled) }
    }

    static var hotKeyEnabled: Bool {
        get { defaults.bool(forKey: Key.hotKeyEnabled) }
        set { set(newValue, for: Key.hotKeyEnabled) }
    }

    static var hotKey: HotKeyShortcut {
        get {
            defaults.data(forKey: Key.hotKey).flatMap { try? JSONDecoder().decode(HotKeyShortcut.self, from: $0) } ?? .standard
        }
        set { set(try? JSONEncoder().encode(newValue), for: Key.hotKey) }
    }

    /// Apps in which holding ⌘V does nothing special (VMs, remote desktops, games).
    static var holdDisabledBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.holdDisabledApps) ?? [] }
        set { set(newValue, for: Key.holdDisabledApps) }
    }

    // MARK: History

    static var historyLimit: Int {
        get { max(defaults.integer(forKey: Key.historyLimit), 10) }
        set { set(newValue, for: Key.historyLimit) }
    }

    static var retentionDays: Int {
        get { max(defaults.integer(forKey: Key.retentionDays), 0) }
        set { set(newValue, for: Key.retentionDays) }
    }

    static var remoteClipboardMode: RemoteClipboardMode {
        get { RemoteClipboardMode(rawValue: defaults.string(forKey: Key.remoteClipboardMode) ?? "") ?? .onDemand }
        set { set(newValue.rawValue, for: Key.remoteClipboardMode) }
    }

    // MARK: Privacy

    static var sensitiveLifetimeSeconds: Int {
        get { max(defaults.integer(forKey: Key.sensitiveLifetime), 10) }
        set { set(newValue, for: Key.sensitiveLifetime) }
    }

    static var detectOneTimeCodes: Bool {
        get { defaults.bool(forKey: Key.detectOneTimeCodes) }
        set { set(newValue, for: Key.detectOneTimeCodes) }
    }

    /// Also empties the pasteboard when a sensitive entry expires (if it is still there).
    static var clearPasteboardAfterSensitive: Bool {
        get { defaults.bool(forKey: Key.clearPasteboardAfterSensitive) }
        set { set(newValue, for: Key.clearPasteboardAfterSensitive) }
    }

    static var customIgnoredBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.customIgnoredApps) ?? [] }
        set { set(newValue, for: Key.customIgnoredApps) }
    }

    /// Entries of the default ignore list the user removed.
    static var removedDefaultIgnoredBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.removedDefaultIgnoredApps) ?? [] }
        set { set(newValue, for: Key.removedDefaultIgnoredApps) }
    }

    static var ignoredBundleIDs: Set<String> {
        DefaultIgnoreList.bundleIDs
            .subtracting(removedDefaultIgnoredBundleIDs)
            .union(customIgnoredBundleIDs)
    }

    /// Capture is paused until this date (`.distantFuture` = until resumed).
    static var pausedUntil: Date? {
        get {
            let value = defaults.double(forKey: Key.pausedUntil)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set { set(newValue?.timeIntervalSince1970 ?? 0, for: Key.pausedUntil) }
    }

    /// Text in images is recognized on this Mac: images become searchable and are
    /// checked for sensitive content.
    static var recognizeTextInImages: Bool {
        get { defaults.bool(forKey: Key.recognizeTextInImages) }
        set { set(newValue, for: Key.recognizeTextInImages) }
    }

    /// Presentation mode is on until then (see `PresentationMode`).
    static var presentationUntil: Date? {
        get {
            let value = defaults.double(forKey: Key.presentationUntil)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set { set(newValue?.timeIntervalSince1970 ?? 0, for: Key.presentationUntil) }
    }

    /// The popup, the notch capsule and the shortcut card ask screen sharing to leave
    /// them out (`NSWindow.sharingType = .none`). Many sharing apps honour it, not all.
    static var hideFromScreenSharing: Bool {
        get { defaults.bool(forKey: Key.hideFromScreenSharing) }
        set { set(newValue, for: Key.hideFromScreenSharing) }
    }

    // MARK: Appearance

    static var showCopyFeedback: Bool {
        get { defaults.bool(forKey: Key.showCopyFeedback) }
        set { set(newValue, for: Key.showCopyFeedback) }
    }

    static var animatePopup: Bool {
        get { defaults.bool(forKey: Key.animatePopup) }
        set { set(newValue, for: Key.animatePopup) }
    }

    /// Website icons need a network request, so they are off unless chosen (ROADMAP D7).
    static var loadFavicons: Bool {
        get { defaults.bool(forKey: Key.loadFavicons) }
        set { set(newValue, for: Key.loadFavicons) }
    }

    /// Pasting without formatting (⇧) also drops tracking parameters from links.
    static var cleanLinks: Bool {
        get { defaults.bool(forKey: Key.cleanLinks) }
        set { set(newValue, for: Key.cleanLinks) }
    }

    /// Also offer beta versions (Sparkle channel "beta").
    static var betaUpdates: Bool {
        get { defaults.bool(forKey: betaUpdatesKey) }
        set { set(newValue, for: betaUpdatesKey) }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { set(newValue, for: Key.hasCompletedOnboarding) }
    }

    // MARK: Screenshot (M11)

    static var screenshotEnabled: Bool {
        get { defaults.bool(forKey: Key.screenshotEnabled) }
        set { set(newValue, for: Key.screenshotEnabled) }
    }

    static var screenshotHotKey: HotKeyShortcut {
        get {
            defaults.data(forKey: Key.screenshotHotKey).flatMap { try? JSONDecoder().decode(HotKeyShortcut.self, from: $0) } ?? .screenshotStandard
        }
        set { set(try? JSONEncoder().encode(newValue), for: Key.screenshotHotKey) }
    }

    /// For scroll tools that flip the wheel direction (Mos, Scroll Reverser).
    static var screenshotScrollReversed: Bool {
        get { defaults.bool(forKey: Key.screenshotScrollReversed) }
        set { set(newValue, for: Key.screenshotScrollReversed) }
    }

    /// The system prompt for Screen Recording was shown once (macOS shows it only once).
    static var screenshotPermissionAsked: Bool {
        get { defaults.bool(forKey: Key.screenshotPermissionAsked) }
        set { set(newValue, for: Key.screenshotPermissionAsked) }
    }

    /// A screenshot worked once on this install: a later denial is a revocation worth a
    /// warning in the menu bar. Users who never used the feature never see it.
    static var screenCaptureWasGranted: Bool {
        get { defaults.bool(forKey: Key.screenCaptureWasGranted) }
        set { set(newValue, for: Key.screenCaptureWasGranted) }
    }

    // MARK: Derived

    static var retentionPolicy: RetentionPolicy {
        RetentionPolicy(
            maxItems: historyLimit,
            maxAge: retentionDays > 0 ? TimeInterval(retentionDays) * 86_400 : nil,
            sensitiveLifetime: TimeInterval(sensitiveLifetimeSeconds)
        )
    }

    static var capturePolicy: CapturePolicy {
        CapturePolicy(retention: retentionPolicy, detection: SensitiveDetectionOptions(detectOneTimeCodes: detectOneTimeCodes))
    }

    static var privacySettings: PrivacySettings {
        PrivacySettings(ignoredBundleIDs: ignoredBundleIDs, pausedUntil: pausedUntil, remoteMode: remoteClipboardMode)
    }
}

/// Apps where holding ⌘V is off by default: virtual machines, remote desktops and
/// screen sharing pass keys to another computer, where ⌘V must arrive unchanged.
enum HoldOffList {
    static let defaultBundleIDs = [
        "com.parallels.desktop.console",
        "com.utmapp.UTM",
        "com.vmware.fusion",
        "org.virtualbox.app.VirtualBoxVM",
        "com.microsoft.rdc.macos",
        "com.microsoft.rdc.mac",
        "com.apple.ScreenSharing",
        "com.teamviewer.TeamViewer",
        "com.anydesk.anydesk",
        "com.citrix.receiver.icaviewer.mac",
    ]
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
