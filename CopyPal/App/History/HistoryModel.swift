import Foundation
import Observation
import CopyPalCore
import CopyPalServices

/// The decrypted history on the main thread for the popup and the history window.
/// Holds at most the history limit (500 by default), so searching it is instant.
@MainActor
@Observable
final class HistoryModel {
    private(set) var items: [ClipItem] = []
    private(set) var favorites: [ClipItem] = []
    private(set) var lastError: String?

    @ObservationIgnored let engine: HistoryEngine

    init(engine: HistoryEngine) {
        self.engine = engine
    }

    /// Re-reads the history from the engine.
    func reload() async {
        do {
            let snapshot = try await engine.snapshot(limit: AppSettings.historyLimit)
            items = snapshot.items
            favorites = snapshot.favorites
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Runs `change` on the engine, then reloads.
    func perform(_ change: @escaping @Sendable (HistoryEngine) async throws -> Void) async {
        do {
            try await change(engine)
        } catch {
            lastError = String(describing: error)
        }
        await reload()
    }

    func item(id: UUID) -> ClipItem? {
        items.first { $0.id == id } ?? favorites.first { $0.id == id }
    }
}
