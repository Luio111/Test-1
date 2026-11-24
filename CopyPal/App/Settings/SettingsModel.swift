import AppKit
import Observation
import UniformTypeIdentifiers
import CopyPalCore
import CopyPalSystem

/// Observable, write-through view of `AppSettings` for SwiftUI: every change is saved
/// at once and applied by the app (ROADMAP M7: no restart needed).
@MainActor
final class SettingsModel: Observable {
    private let registrar = ObservationRegistrar()

    private func read<Value>(_ keyPath: KeyPath<SettingsModel, Value>, _ value: () -> Value) -> Value {
        registrar.access(self, keyPath: keyPath)
        return value()
    }

    private func write<Value>(_ keyPath: KeyPath<SettingsModel, Value>, _ change: () -> Void) {
        registrar.withMutation(of: self, keyPath: keyPath, change)
    }

    // MARK: General

    var holdGestureEnabled: Bool {
        get { read(\.holdGestureEnabled) { AppSettings.holdGestureEnabled } }
        set { write(\.holdGestureEnabled) { AppSettings.holdGestureEnabled = newValue } }
    }

    var holdThreshold: Double {
        get { read(\.holdThreshold) { AppSettings.holdThreshold } }
        set { write(\.holdThreshold) { AppSettings.holdThreshold = newValue } }
    }

    var hotKeyEnabled: Bool {
        get { read(\.hotKeyEnabled) { AppSettings.hotKeyEnabled } }
        set { write(\.hotKeyEnabled) { AppSettings.hotKeyEnabled = newValue } }
    }

    var hotKey: HotKeyShortcut {
        get { read(\.hotKey) { AppSettings.hotKey } }
        set { write(\.hotKey) { AppSettings.hotKey = newValue } }
    }

    var animatePopup: Bool {
        get { read(\.animatePopup) { AppSettings.animatePopup } }
        set { write(\.animatePopup) { AppSettings.animatePopup = newValue } }
    }

    var showCopyFeedback: Bool {
        get { read(\.showCopyFeedback) { AppSettings.showCopyFeedback } }
        set { write(\.showCopyFeedback) { AppSettings.showCopyFeedback = newValue } }
    }

    var holdDisabledBundleIDs: [String] {
        get { read(\.holdDisabledBundleIDs) { AppSettings.holdDisabledBundleIDs } }
        set { write(\.holdDisabledBundleIDs) { AppSettings.holdDisabledBundleIDs = newValue } }
    }

    // MARK: Screenshot

    var screenshotEnabled: Bool {
        get { read(\.screenshotEnabled) { AppSettings.screenshotEnabled } }
        set { write(\.screenshotEnabled) { AppSettings.screenshotEnabled = newValue } }
    }

    var screenshotHotKey: HotKeyShortcut {
        get { read(\.screenshotHotKey) { AppSettings.screenshotHotKey } }
        set { write(\.screenshotHotKey) { AppSettings.screenshotHotKey = newValue } }
    }

    var screenshotScrollReversed: Bool {
        get { read(\.screenshotScrollReversed) { AppSettings.screenshotScrollReversed } }
        set { write(\.screenshotScrollReversed) { AppSettings.screenshotScrollReversed = newValue } }
    }

    // MARK: History

    var historyLimit: Int {
        get { read(\.historyLimit) { AppSettings.historyLimit } }
        set { write(\.historyLimit) { AppSettings.historyLimit = newValue } }
    }

    var retentionDays: Int {
        get { read(\.retentionDays) { AppSettings.retentionDays } }
        set { write(\.retentionDays) { AppSettings.retentionDays = newValue } }
    }

    var remoteClipboardMode: RemoteClipboardMode {
        get { read(\.remoteClipboardMode) { AppSettings.remoteClipboardMode } }
        set { write(\.remoteClipboardMode) { AppSettings.remoteClipboardMode = newValue } }
    }

    var loadFavicons: Bool {
        get { read(\.loadFavicons) { AppSettings.loadFavicons } }
        set { write(\.loadFavicons) { AppSettings.loadFavicons = newValue } }
    }

    var cleanLinks: Bool {
        get { read(\.cleanLinks) { AppSettings.cleanLinks } }
        set { write(\.cleanLinks) { AppSettings.cleanLinks = newValue } }
    }

    var recognizeTextInImages: Bool {
        get { read(\.recognizeTextInImages) { AppSettings.recognizeTextInImages } }
        set { write(\.recognizeTextInImages) { AppSettings.recognizeTextInImages = newValue } }
    }

    var hideFromScreenSharing: Bool {
        get { read(\.hideFromScreenSharing) { AppSettings.hideFromScreenSharing } }
        set { write(\.hideFromScreenSharing) { AppSettings.hideFromScreenSharing = newValue } }
    }

    // MARK: Privacy

    var sensitiveLifetimeSeconds: Int {
        get { read(\.sensitiveLifetimeSeconds) { AppSettings.sensitiveLifetimeSeconds } }
        set { write(\.sensitiveLifetimeSeconds) { AppSettings.sensitiveLifetimeSeconds = newValue } }
    }

    var detectOneTimeCodes: Bool {
        get { read(\.detectOneTimeCodes) { AppSettings.detectOneTimeCodes } }
        set { write(\.detectOneTimeCodes) { AppSettings.detectOneTimeCodes = newValue } }
    }

    var clearPasteboardAfterSensitive: Bool {
        get { read(\.clearPasteboardAfterSensitive) { AppSettings.clearPasteboardAfterSensitive } }
        set { write(\.clearPasteboardAfterSensitive) { AppSettings.clearPasteboardAfterSensitive = newValue } }
    }

    var customIgnoredBundleIDs: [String] {
        get { read(\.customIgnoredBundleIDs) { AppSettings.customIgnoredBundleIDs } }
        set { write(\.customIgnoredBundleIDs) { AppSettings.customIgnoredBundleIDs = newValue } }
    }

    var removedDefaultIgnoredBundleIDs: [String] {
        get { read(\.removedDefaultIgnoredBundleIDs) { AppSettings.removedDefaultIgnoredBundleIDs } }
        set { write(\.removedDefaultIgnoredBundleIDs) { AppSettings.removedDefaultIgnoredBundleIDs = newValue } }
    }

    var pausedUntil: Date? {
        get { read(\.pausedUntil) { AppSettings.pausedUntil } }
        set { write(\.pausedUntil) { AppSettings.pausedUntil = newValue } }
    }

    var betaUpdates: Bool {
        get { read(\.betaUpdates) { AppSettings.betaUpdates } }
        set { write(\.betaUpdates) { AppSettings.betaUpdates = newValue } }
    }

    // MARK: Helpers

    func isIgnored(_ bundleID: String) -> Bool {
        if DefaultIgnoreList.bundleIDs.contains(bundleID) {
            return !removedDefaultIgnoredBundleIDs.contains(bundleID)
        }
        return customIgnoredBundleIDs.contains(bundleID)
    }

    func setIgnored(_ bundleID: String, _ ignored: Bool) {
        if DefaultIgnoreList.bundleIDs.contains(bundleID) {
            var removed = Set(removedDefaultIgnoredBundleIDs)
            if ignored { removed.remove(bundleID) } else { removed.insert(bundleID) }
            removedDefaultIgnoredBundleIDs = removed.sorted()
        } else if ignored {
            if !customIgnoredBundleIDs.contains(bundleID) {
                customIgnoredBundleIDs.append(bundleID)
            }
        } else {
            customIgnoredBundleIDs.removeAll { $0 == bundleID }
        }
    }

    func restoreDefaultIgnoreList() {
        removedDefaultIgnoredBundleIDs = []
    }

    /// Lets the user pick an app; returns its bundle ID.
    func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Hinzufügen")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    func displayName(for bundleID: String) -> String {
        if let entry = DefaultIgnoreList.entries.first(where: { $0.bundleID == bundleID }) {
            return entry.name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}
