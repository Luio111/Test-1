import AppKit
import Observation
import CopyPalCore
import CopyPalServices
import CopyPalSystem

/// One pasteboard change as the lab shows it: type identifiers, source app, size and
/// timing. Never contains clipboard content.
struct CaptureLogEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let changeCount: Int
    let types: [String]
    let sourceBundleID: String?
    let outcome: String
    let byteSize: Int?
    let readMilliseconds: Double?
}

/// Watches the pasteboard and records copies (ROADMAP §1.3): types first (markers,
/// ignore list, pause, iPhone handling), then the content off the main thread, then
/// the engine stores it encrypted. Changes are processed strictly in order.
@MainActor
@Observable
final class CaptureCoordinator {
    private(set) var log: [CaptureLogEntry] = []
    /// Why capture currently cannot run (pasteboard privacy setting), if it cannot.
    private(set) var blockedReason: CaptureSkipReason?

    /// A new entry was stored (for the "Copied ✓" feedback).
    @ObservationIgnored var onStored: ((ClipItem) -> Void)?

    @ObservationIgnored let monitor: PasteboardMonitor
    @ObservationIgnored private let engine: HistoryEngine
    @ObservationIgnored private let history: HistoryModel
    @ObservationIgnored private let timeSource: any TimeSource
    @ObservationIgnored private var queue: Task<Void, Never>?

    init(monitor: PasteboardMonitor, engine: HistoryEngine, history: HistoryModel, timeSource: any TimeSource) {
        self.monitor = monitor
        self.engine = engine
        self.history = history
        self.timeSource = timeSource
        monitor.onChange = { [weak self] change in
            self?.enqueue(change)
        }
    }

    func start() {
        monitor.start()
    }

    func stop() {
        monitor.stop()
    }

    var isPaused: Bool {
        AppSettings.privacySettings.isPaused(at: timeSource.now())
    }

    /// Call after CopyPal itself wrote the pasteboard (pasting from the history).
    func registerOwnWrite(changeCount: Int) {
        monitor.registerOwnWrite(changeCount: changeCount)
    }

    /// Waits until every change noticed so far is processed (tests, self-test).
    func drain() async {
        monitor.poll()
        await queue?.value
    }

    private func enqueue(_ change: PasteboardMonitor.Change) {
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            await self?.process(change)
        }
    }

    private func process(_ change: PasteboardMonitor.Change) async {
        await engine.pasteboardDidChange(to: change.changeCount)
        if change.isOwnWrite {
            record(change, outcome: describe(.ownWrite))
            return
        }

        let access = PasteboardInspector.accessStatus(of: monitor.pasteboard)
        if access == .ask || access == .alwaysDeny {
            blockedReason = .accessDenied
            record(change, outcome: describe(.accessDenied))
            return
        }
        blockedReason = nil

        let decision = PrivacyFilter.decide(
            types: change.types,
            sourceBundleID: change.sourceBundleID,
            settings: AppSettings.privacySettings,
            now: timeSource.now()
        )
        switch decision {
        case let .skip(reason):
            record(change, outcome: describe(reason))
        case .recordRemotePlaceholder:
            do {
                _ = try await engine.recordRemotePlaceholder(changeCount: change.changeCount)
                record(change, outcome: "vom iPhone (Inhalt erst bei Auswahl)")
                await history.reload()
            } catch {
                record(change, outcome: "Fehler: \(error)")
            }
        case let .read(origin):
            let result = await PasteboardReader.read(
                pasteboardName: monitor.pasteboard.name.rawValue,
                expectedChangeCount: change.changeCount,
                budget: PasteboardReader.Budget(AppSettings.retentionPolicy)
            )
            switch result {
            case let .skipped(reason):
                record(change, outcome: describe(reason))
            case let .content(content, milliseconds):
                var content = content
                content.sourceBundleID = change.sourceBundleID
                content.origin = origin
                await store(content, change: change, milliseconds: milliseconds)
            }
        }
    }

    private func store(_ content: CapturedContent, change: PasteboardMonitor.Change, milliseconds: Double) async {
        do {
            let outcome = try await engine.capture(content)
            switch outcome {
            case let .skipped(reason):
                record(change, outcome: describe(reason), bytes: content.byteSize, milliseconds: milliseconds)
            case let .stored(result):
                let text = switch result {
                case .inserted: "gespeichert"
                case .movedToTop: "nach oben gerückt (Duplikat)"
                case .unchanged: "unverändert (wie der neueste Eintrag)"
                }
                let sensitivity = result.item.sensitivity.map { " · sensibel (\($0.rawValue))" } ?? ""
                record(change, outcome: "\(text) · \(result.item.kind.rawValue)\(sensitivity)", bytes: content.byteSize, milliseconds: milliseconds)
                await history.reload()
                if case .unchanged = result {} else {
                    onStored?(result.item)
                }
            }
        } catch {
            record(change, outcome: "Fehler: \(error)", bytes: content.byteSize, milliseconds: milliseconds)
        }
    }

    private func record(_ change: PasteboardMonitor.Change, outcome: String, bytes: Int? = nil, milliseconds: Double? = nil) {
        log.append(CaptureLogEntry(
            date: Date(),
            changeCount: change.changeCount,
            types: change.types,
            sourceBundleID: change.sourceBundleID,
            outcome: outcome,
            byteSize: bytes,
            readMilliseconds: milliseconds
        ))
        if log.count > 50 {
            log.removeFirst(log.count - 50)
        }
    }

    private func describe(_ reason: CaptureSkipReason) -> String {
        switch reason {
        case .concealed: "übersprungen: als geheim markiert"
        case .transient: "übersprungen: als vorübergehend markiert"
        case .autoGenerated: "übersprungen: automatisch erzeugt"
        case .empty: "übersprungen: leer"
        case .unsupported: "übersprungen: kein bekanntes Format"
        case .tooLarge: "übersprungen: zu groß"
        case .ignoredApp: "übersprungen: App wird ignoriert"
        case .paused: "übersprungen: Aufzeichnung pausiert"
        case .remoteIgnored: "übersprungen: iPhone-Kopien ignoriert"
        case .timedOut: "übersprungen: Lesen dauerte zu lange"
        case .changedWhileReading: "übersprungen: während des Lesens geändert"
        case .ownWrite: "eigener Schreibvorgang"
        case .accessDenied: "übersprungen: Zugriff auf die Zwischenablage nicht erlaubt"
        }
    }
}
