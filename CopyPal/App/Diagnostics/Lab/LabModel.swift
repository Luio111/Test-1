#if DEBUG
import AppKit
import Observation
import CopyPalCore
import CopyPalSystem

/// Live state for the lab window (debug builds only): tap status, settings and
/// measurements (M1), every pasteboard change and write tests (M2).
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

    private(set) var captureLog: [CaptureLogEntry] = []
    private(set) var notchOverlayVisible = false
    @ObservationIgnored private let notchOverlay = NotchOverlayController()
    private(set) var historyCount = 0
    private(set) var diskUsage = 0

    /// Bound to the sliders and pickers; `apply…` persists them.
    var holdThreshold: Double
    var pasteDelay: Double
    var remoteMode: RemoteClipboardMode

    /// Screenshot (M11): tuning aids, not persisted.
    var showsDetectedRegions = false
    var scrollsWithoutCursorWarp = false
    private(set) var screenshotFreeze: Double?
    private(set) var screenshotStep: String?

    @ObservationIgnored private let app: AppController
    private var input: InputCoordinator { app.input }
    @ObservationIgnored private var timer: Timer?

    init(app: AppController) {
        self.app = app
        layout = app.input.layout
        holdThreshold = AppSettings.holdThreshold
        pasteDelay = AppSettings.pasteDelayMilliseconds
        remoteMode = AppSettings.remoteClipboardMode
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
        notchOverlay.hide()
        notchOverlayVisible = false
        timer?.invalidate()
        timer = nil
        input.tap.diagnostics.isRecording = false
    }

    func applyHoldThreshold() {
        AppSettings.holdThreshold = holdThreshold
    }

    func toggleNotchOverlay() {
        notchOverlay.toggle()
        notchOverlayVisible = notchOverlay.isVisible
    }

    func applyRemoteMode() {
        AppSettings.remoteClipboardMode = remoteMode
    }

    func applyScreenshotOptions() {
        app.screenshot.showsDetectedRegions = showsDetectedRegions
        app.screenshot.scrollsWithoutCursorWarp = scrollsWithoutCursorWarp
    }

    /// M2 test: writes a sample normally (reaches the iPhone) or "this Mac only".
    func writeTest(localOnly: Bool) {
        let text = localOnly
            ? "CopyPal-Test: nur auf diesem Mac (\(Date().formatted(date: .omitted, time: .standard)))"
            : "CopyPal-Test: normal (\(Date().formatted(date: .omitted, time: .standard)))"
        let changeCount = PasteboardWriter.write(
            [ClipRepresentation(type: PasteboardTypeID.plainText, data: Data(text.utf8))],
            options: PasteboardWriter.Options(localOnly: localOnly)
        )
        app.capture.registerOwnWrite(changeCount: changeCount)
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
        captureLog = app.capture.log
        historyCount = app.history.items.count
        diskUsage = app.engine.store.diskUsage()
        screenshotFreeze = app.screenshot.lastFreezeMilliseconds
        screenshotStep = app.screenshot.lastStepDescription
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
            "Zugriff auf Zwischenablage: \(PasteboardInspector.accessStatus())",
            "iPhone-Kopien: \(remoteMode.rawValue) · Verlauf: \(historyCount) Einträge · \(diskUsage / 1024) KB auf der Platte",
            "",
            "Letzte Ereignisse (Taste · Modifier · Quelle · Entscheidung):",
        ]
        lines += snapshot.entries.suffix(15).map(Self.describe)
        lines.append("")
        lines.append("Letzte Kopien (Formate · Quelle · Größe · Lesedauer → Ergebnis):")
        lines += captureLog.suffix(15).map(Self.describe)
        return lines.joined(separator: "\n")
    }

    /// Type identifiers and sizes only – never content.
    static func describe(_ entry: CaptureLogEntry) -> String {
        let types = entry.types.prefix(6).joined(separator: ", ") + (entry.types.count > 6 ? ", …" : "")
        let size = entry.byteSize.map { "\($0) B" } ?? "–"
        let time = entry.readMilliseconds.map { String(format: "%.1f ms", $0) } ?? "–"
        return "#\(entry.changeCount) [\(types)] · \(entry.sourceBundleID ?? "?") · \(size) · \(time) → \(entry.outcome)"
    }

    static func describe(_ entry: InputLogEntry) -> String {
        let key = entry.keyCode.map { "Taste \($0)" } ?? ""
        let repeatMark = entry.isRepeat ? " (Wdh.)" : ""
        let source = entry.keyCode == nil ? "" : " · Quelle \(entry.sourceState)/\(entry.sourcePID)"
        return "\(entry.kind) \(key)\(repeatMark) \(entry.modifiers.symbols)\(source) → \(entry.decision)"
    }
}
#endif
