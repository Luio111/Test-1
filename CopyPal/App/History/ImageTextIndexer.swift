import Foundation
import CopyPalCore
import CopyPalServices

/// Recognizes the text in images of the history, on this Mac: new copies and
/// screenshots at once, older images one by one after launch. The text makes an image
/// searchable; an IBAN, a card number or a key in it turns the entry sensitive like a
/// copied one. One image at a time, at utility priority, in the helper process
/// (``TextRecognitionClient``).
@MainActor
final class ImageTextIndexer {
    private let history: HistoryModel
    private let recognition: TextRecognitionClient
    private var queue: [UUID] = []
    private var isRunning = false
    /// Something changed that the lists should show (new search text, a sensitive hit).
    private var needsReload = false
    /// Bytes handed back to the system after the last batch (self-test).
    private(set) var releasedBytes = 0

    init(history: HistoryModel, recognition: TextRecognitionClient) {
        self.history = history
        self.recognition = recognition
    }

    /// Nothing queued or running (self-test: measure idle CPU only after this).
    var isIdle: Bool {
        !isRunning && queue.isEmpty
    }

    func enqueue(_ id: UUID) {
        guard AppSettings.recognizeTextInImages, !queue.contains(id) else { return }
        queue.append(id)
        runNext()
    }

    /// Images stored before (or while the setting was off), newest first.
    func catchUp() {
        guard AppSettings.recognizeTextInImages else { return }
        let engine = history.engine
        Task {
            let ids = (try? await engine.imagesAwaitingTextRecognition(limit: 200)) ?? []
            for id in ids {
                enqueue(id)
            }
        }
    }

    private func runNext() {
        guard !isRunning else { return }
        guard !queue.isEmpty else {
            if needsReload {
                needsReload = false
                Task { await history.reload() }
            }
            // Each image was decrypted whole (up to 200 MB for a long screenshot): hand the
            // freed pages back now instead of leaving them with the allocator.
            releasedBytes = malloc_zone_pressure_relief(nil, 0)
            return
        }
        isRunning = true
        let id = queue.removeFirst()
        let engine = history.engine
        let recognition = self.recognition
        Task(priority: .utility) {
            let found = await Self.recognize(id, engine: engine, recognition: recognition)
            needsReload = true
            if found {
                // A sensitive image must not stay visible unmasked until the queue is done.
                needsReload = false
                await history.reload()
            }
            isRunning = false
            runNext()
        }
    }

    /// True when the image turned out to contain sensitive content.
    nonisolated private static func recognize(_ id: UUID, engine: HistoryEngine, recognition: TextRecognitionClient) async -> Bool {
        guard let png = try? await engine.representations(of: id).first(where: { $0.type == PasteboardTypeID.png })?.data else {
            return false
        }
        let text = await recognition.text(inImageData: png)
        let sensitivity = try? await engine.applyRecognizedText(id, text: text)
        return sensitivity != nil
    }
}
