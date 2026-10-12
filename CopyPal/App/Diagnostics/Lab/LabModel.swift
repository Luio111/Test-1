#if DEBUG
import AppKit
import Observation
import CopyPalCore
import CopyPalSystem

/// Live state for the lab window (debug builds only): tap status, settings and
/// measurements for milestone M1.
@MainActor
@Observable
final class LabModel {
    private(set) var snapshot = InputDiagnostics.Snapshot.empty
    private(set) var tapRunning = false
    private(set) var tapEnabled = false
    private(set) var accessibility: PermissionState = .denied
    private(set) var secureInput = SecureInput.Status.off
    private(set) var layout: KeyboardLayout.Resolution
    private(set) var reportCopied = false

    /// Bound to the sliders; `apply…` persists them.
    var holdThreshold: Double
    var pasteDelay: Double

    @ObservationIgnored private let input: InputCoordinator
    @ObservationIgnored private var timer: Timer?

    init(input: InputCoordinator) {
        self.input = input
        layout = input.layout
        holdThreshold = AppSettings.holdThreshold
        pasteDelay = AppSettings.pasteDelayMilliseconds
    }

    func start() {
        input.tap.diagnostics.isRecording = true
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        input.tap.diagnostics.isRecording = false
    }

    func applyHoldThreshold() {
        input.setHoldThreshold(holdThreshold)
    }

    func applyPasteDelay() {
        AppSettings.pasteDelayMilliseconds = pasteDelay
    }

    func resetMeasurements() {
        input.tap.diagnostics.reset()
        refresh()
    }

    func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report(), forType: .string)
        reportCopied = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.reportCopied = false
        }
    }

    private func refresh() {
        snapshot = input.tap.diagnostics.snapshot()
        tapRunning = input.tap.isRunning
        tapEnabled = input.tap.isEnabled
        accessibility = AccessibilityPermission.state
        secureInput = SecureInput.current()
        layout = input.layout
    }

    /// Plain-text summary for the PR comment. Key codes only, no typed characters.
    private func report() -> String {
        func format(_ summary: LatencySummary?) -> String {
            guard let summary else { return "keine Messung" }
            return String(format: "Median %.0f ms · p90 %.0f ms · max %.0f ms (n = %ld)", summary.median, summary.p90, summary.max, summary.count)
        }
        var lines = [
            "CopyPal Labor (M1)",
            "App: \(AppInfo.version) (\(AppInfo.build)) · \(AppInfo.buildEnvironment) · macOS \(AppInfo.osVersion)",
            "Tap: \(tapRunning ? (tapEnabled ? "läuft" : "pausiert") : "aus") · Bedienungshilfen: \(accessibility == .granted ? "erteilt" : "nicht erteilt")",
            "Sichere Eingabe: \(secureInput.isEnabled ? "aktiv (\(secureInput.appName ?? "unbekannte App"))" : "aus")",
            "Layout: \(layout.layoutName) · ⌘V-Taste: \(layout.pasteKeyCode)\(layout.resolved ? "" : " (Standard)")",
            String(format: "Halteschwelle: %.2f s · Wartezeit vor dem Einfügen: %.0f ms", holdThreshold, pasteDelay),
            "Tipp-Dauer (Zusatzverzögerung): \(format(snapshot.tap))",
            "Pop-up-Latenz: \(format(snapshot.popup))",
            String(format: "Längster Callback: %.2f ms", snapshot.slowestCallback),
            "",
            "Letzte Ereignisse (Taste · Modifier · Quelle · Entscheidung):",
        ]
        lines += snapshot.entries.suffix(15).map(Self.describe)
        return lines.joined(separator: "\n")
    }

    static func describe(_ entry: InputLogEntry) -> String {
        let key = entry.keyCode.map { "Taste \($0)" } ?? ""
        let repeatMark = entry.isRepeat ? " (Wdh.)" : ""
        let source = entry.keyCode == nil ? "" : " · Quelle \(entry.sourceState)/\(entry.sourcePID)"
        return "\(entry.kind) \(key)\(repeatMark) \(entry.modifiers.symbols)\(source) → \(entry.decision)"
    }
}
#endif
