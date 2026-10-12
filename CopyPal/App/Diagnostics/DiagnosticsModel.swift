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
