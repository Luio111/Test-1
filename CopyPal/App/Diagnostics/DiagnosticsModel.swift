import AppKit
import Observation
import CopyPalCore
import CopyPalSystem

/// State behind the diagnostics window. Refreshes the Accessibility state every
/// second while the window is open, so granting it in System Settings shows up live.
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

    var warnings: [String] {
        DiagnosticsReport.warnings(for: snapshot)
    }

    func refresh() {
        snapshot = Self.makeSnapshot(probe: snapshot.pasteboardProbe)
    }

    func runPasteboardProbe() {
        snapshot = Self.makeSnapshot(probe: PasteboardInspector.probe())
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
        refresh()
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DiagnosticsReport.text(for: snapshot), forType: .string)

        reportCopied = true
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
                self?.refreshAccessibility()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshAccessibility() {
        let state = AccessibilityPermission.state
        if state != snapshot.accessibility {
            snapshot.accessibility = state
        }
    }

    private static func makeSnapshot(probe: PasteboardProbe?) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            appVersion: AppInfo.version,
            buildNumber: AppInfo.build,
            bundleIdentifier: AppInfo.bundleIdentifier,
            osVersion: AppInfo.osVersion,
            signing: CodeSigningInspector.currentProcess(),
            accessibility: AccessibilityPermission.state,
            pasteboardAccess: PasteboardInspector.accessStatus(),
            pasteboardProbe: probe
        )
    }
}
