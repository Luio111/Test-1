import AppKit
import Observation
import CopyPalCore
import CopyPalSystem

/// State behind the diagnostics window. While the window is open, Accessibility and
/// the pasteboard setting are re-read every second, so changes made in System
/// Settings show up live.
@MainActor
@Observable
final class DiagnosticsModel {
    private(set) var snapshot: DiagnosticsSnapshot
    private(set) var reportCopied = false
    /// The newest crash report of CopyPal, if macOS wrote one.
    private(set) var latestCrash: CrashReports.Report?
    private(set) var crashCopied = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var copiedResetTask: Task<Void, Never>?

    init() {
        snapshot = Self.makeSnapshot(probe: nil)
    }

    var warnings: [DiagnosticsWarning] {
        DiagnosticsWarning.warnings(for: snapshot)
    }

    /// Re-reads everything, keeping the last probe result.
    func refresh() {
        snapshot = Self.makeSnapshot(probe: snapshot.pasteboardProbe)
        latestCrash = CrashReports.latest()
    }

    /// Copies the newest crash report, with the home folder shortened to "~".
    func copyCrashReport() {
        guard let latestCrash, let text = CrashReports.anonymizedText(of: latestCrash) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        crashCopied = true
        announce(String(localized: "Absturzbericht kopiert"))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.crashCopied = false
        }
    }

    func runPasteboardProbe() {
        let probe = PasteboardInspector.probe()
        snapshot = Self.makeSnapshot(probe: probe)
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
        refresh()
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    func copyReport() {
        refresh()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DiagnosticsReport.text(for: snapshot), forType: .string)

        reportCopied = true
        announce(String(localized: "Bericht kopiert"))
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.reportCopied = false
        }
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshLiveState()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Cheap reads only (no code-signing lookup), so it can run every second.
    private func refreshLiveState() {
        let accessibility = AccessibilityPermission.state
        if accessibility != snapshot.accessibility {
            snapshot.accessibility = accessibility
        }
        let pasteboardAccess = PasteboardInspector.accessStatus()
        if pasteboardAccess != snapshot.pasteboardAccess {
            snapshot.pasteboardAccess = pasteboardAccess
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private static func makeSnapshot(probe: PasteboardProbe?) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            appVersion: AppInfo.version,
            buildNumber: AppInfo.build,
            bundleIdentifier: AppInfo.bundleIdentifier,
            buildEnvironment: AppInfo.buildEnvironment,
            osVersion: AppInfo.osVersion,
            signing: CodeSigningInspector.currentProcess(),
            accessibility: AccessibilityPermission.state,
            pasteboardAccess: PasteboardInspector.accessStatus(),
            pasteboardProbe: probe
        )
    }
}

/// Crash reports macOS writes for CopyPal (`~/Library/Logs/DiagnosticReports`).
enum CrashReports {
    struct Report: Equatable {
        var url: URL
        var date: Date
    }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    static func latest() -> Report? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return nil
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("CopyPal") && ["ips", "crash"].contains($0.pathExtension) }
            .compactMap { url in
                (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate).map { Report(url: url, date: $0) }
            }
            .max { $0.date < $1.date }
    }

    /// Crash reports contain no clipboard content; the user's home path is shortened.
    static func anonymizedText(of report: Report) -> String? {
        guard let text = try? String(contentsOf: report.url, encoding: .utf8) else { return nil }
        return text.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
