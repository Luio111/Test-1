import AppKit
import CopyPalCore
import CopyPalServices
import CopyPalSystem

/// Pastes a history entry (ROADMAP §1.3): put it on the pasteboard (sensitive entries
/// "this Mac only" and concealed), wait until the target app is in front again, then
/// post ⌘V. Without Accessibility, or when the target app lost focus, the entry
/// stays on the pasteboard and a hint says "Press ⌘V now".
@MainActor
final class PasteController {
    enum Outcome: Equatable {
        case pasted
        /// On the pasteboard, but ⌘V was not posted.
        case onPasteboard(Reason)
        case unavailable

        enum Reason: Equatable {
            case noPermission
            case targetNotInFront
        }
    }

    private let history: HistoryModel
    private let capture: CaptureCoordinator
    private let input: InputCoordinator
    private let toast: ToastController
    /// Own writes of sensitive entries, to clear the pasteboard when they expire.
    private(set) var sensitiveWrites: [UUID: Int] = [:]

    init(history: HistoryModel, capture: CaptureCoordinator, input: InputCoordinator, toast: ToastController) {
        self.history = history
        self.capture = capture
        self.input = input
        self.toast = toast
    }

    @discardableResult
    func paste(_ item: ClipItem, plainText: Bool, targetProcessID: pid_t?) async -> Outcome {
        guard let item = await materializeIfNeeded(item),
              let representations = try? await history.engine.representations(of: item.id),
              !representations.isEmpty else {
            NSSound.beep()
            toast.show(String(localized: "Eintrag nicht mehr verfügbar"), systemImage: "exclamationmark.circle")
            return .unavailable
        }

        putOnPasteboard(item, representations: representations, plainText: plainText)
        await history.perform { engine in
            _ = try await engine.markUsed(item.id)
        }

        guard input.canPaste else {
            toast.show(String(localized: "Jetzt ⌘V drücken"), systemImage: "command")
            return .onPasteboard(.noPermission)
        }
        // Give focus a moment to return to the target app, then paste only if it is
        // still in front; otherwise the entry just stays on the pasteboard.
        try? await Task.sleep(for: .milliseconds(Int(AppSettings.pasteDelayMilliseconds)))
        if let targetProcessID, NSWorkspace.shared.frontmostApplication?.processIdentifier != targetProcessID {
            toast.show(String(localized: "In der Zwischenablage – mit ⌘V einfügen"), systemImage: "doc.on.clipboard")
            return .onPasteboard(.targetNotInFront)
        }
        PasteSynthesizer.postPaste(keyCode: input.layout.pasteKeyCode)
        return .pasted
    }

    /// Copies an entry to the pasteboard without pasting (history window, "Copy").
    func copy(_ item: ClipItem, plainText: Bool = false) async {
        guard let item = await materializeIfNeeded(item),
              let representations = try? await history.engine.representations(of: item.id),
              !representations.isEmpty else {
            NSSound.beep()
            return
        }
        putOnPasteboard(item, representations: representations, plainText: plainText)
        await history.perform { engine in
            _ = try await engine.markUsed(item.id)
        }
    }

    /// Empties the pasteboard if it still holds the given expired sensitive entries.
    func clearPasteboard(ifStillHolding expired: [UUID]) {
        let pasteboard = capture.monitor.pasteboard
        for id in expired {
            guard let changeCount = sensitiveWrites.removeValue(forKey: id) else { continue }
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                capture.registerOwnWrite(changeCount: pasteboard.changeCount)
            }
        }
    }

    private func putOnPasteboard(_ item: ClipItem, representations: [ClipRepresentation], plainText: Bool) {
        let options = PasteboardWriter.Options(
            plainTextOnly: plainText,
            localOnly: item.localOnly || item.isSensitive,
            concealed: item.isSensitive
        )
        let changeCount = PasteboardWriter.write(representations, to: capture.monitor.pasteboard, options: options)
        capture.registerOwnWrite(changeCount: changeCount)
        if item.isSensitive {
            sensitiveWrites[item.id] = changeCount
        }
    }

    /// An iPhone copy recorded from its types only: read it now, at the user's request.
    private func materializeIfNeeded(_ item: ClipItem) async -> ClipItem? {
        guard let changeCount = await history.engine.remotePlaceholderChangeCount(item.id) else {
            return item
        }
        let pasteboard = capture.monitor.pasteboard
        guard pasteboard.changeCount == changeCount else { return nil }
        let result = await PasteboardReader.read(
            pasteboardName: pasteboard.name.rawValue,
            expectedChangeCount: changeCount,
            budget: PasteboardReader.Budget(AppSettings.retentionPolicy),
            timeout: 10
        )
        guard case let .content(content, _) = result,
              case let .stored(saved)? = try? await history.engine.materializeRemote(item.id, with: content) else {
            return nil
        }
        await history.reload()
        return saved.item
    }
}
