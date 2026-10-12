import CopyPalCore
import CopyPalStorage
import Foundation

/// What happened to a copy.
public enum CaptureOutcome: Sendable, Equatable {
    case stored(SaveResult)
    case skipped(CaptureSkipReason)
}

/// The history's current state for the UI: newest first, plus the favorites.
public struct HistorySnapshot: Sendable, Equatable {
    public var items: [ClipItem]
    public var favorites: [ClipItem]

    public init(items: [ClipItem] = [], favorites: [ClipItem] = []) {
        self.items = items
        self.favorites = favorites
    }

    public static let empty = HistorySnapshot()
}

/// Settings the engine applies to every copy.
public struct CapturePolicy: Sendable, Equatable {
    public var retention: RetentionPolicy
    public var detection: SensitiveDetectionOptions

    public init(retention: RetentionPolicy = .standard, detection: SensitiveDetectionOptions = SensitiveDetectionOptions()) {
        self.retention = retention
        self.detection = detection
    }
}

/// Turns copies into history entries and runs every change to the history, off the
/// main thread (ROADMAP §1.3): classify → detect sensitive content → size limits →
/// store encrypted (duplicates move to the top) → retention.
public actor HistoryEngine {
    /// Thread-safe itself; also read directly (thumbnails, disk usage).
    public nonisolated let store: ClipStore
    private let timeSource: any TimeSource
    private var policy: CapturePolicy
    /// iPhone copies recorded from their types only (`RemoteClipboardMode.onDemand`),
    /// with the pasteboard change they belong to.
    private var remotePlaceholders: [UUID: Int] = [:]

    public init(store: ClipStore, policy: CapturePolicy = CapturePolicy(), timeSource: any TimeSource = SystemTimeSource()) {
        self.store = store
        self.policy = policy
        self.timeSource = timeSource
    }

    public func setPolicy(_ policy: CapturePolicy) {
        self.policy = policy
    }

    public var currentPolicy: CapturePolicy {
        policy
    }

    // MARK: Capture

    public func capture(_ content: CapturedContent) throws -> CaptureOutcome {
        guard let classification = ContentClassifier.classify(content) else {
            return .skipped(.unsupported)
        }
        let representations = Self.storedRepresentations(of: content, kind: classification.kind)
        let byteSize = representations.reduce(0) { $0 + $1.data.count }
        guard HistoryRules.accepts(kind: classification.kind, byteSize: byteSize, policy: policy.retention) else {
            return .skipped(.tooLarge)
        }

        var preview = classification.preview
        let match = classification.text.flatMap { SensitiveContentDetector.detect($0, options: policy.detection) }
        if let match {
            preview.masked = match.masked
            preview.searchText = ""
        }
        let now = timeSource.now()
        let clip = NewClip(
            kind: classification.kind,
            preview: preview,
            representations: representations,
            fingerprintSource: classification.fingerprintSource,
            sourceBundleID: content.sourceBundleID,
            origin: content.origin,
            sensitivity: match?.kind,
            expiresAt: HistoryRules.expiry(for: match?.kind, policy: policy.retention, now: now),
            // Sensitive entries and iPhone copies never leave this Mac again.
            localOnly: match != nil || content.origin == .remoteDevice
        )
        let result = try store.save(clip)
        if case .inserted = result {
            try store.applyRetention(policy.retention)
        }
        return .stored(result)
    }

    /// Keeps only what CopyPal can paste back: the types in `PasteboardTypeID.stored`;
    /// for files only the references.
    static func storedRepresentations(of content: CapturedContent, kind: ClipKind) -> [ClipRepresentation] {
        let allowed: Set<String> = kind == .files
            ? [PasteboardTypeID.fileURL, PasteboardTypeID.plainText]
            : Set(PasteboardTypeID.stored)
        return content.representations.filter { allowed.contains($0.type) }
    }

    /// Records that something was copied on another device, without reading it.
    public func recordRemotePlaceholder(changeCount: Int) throws -> ClipItem {
        removeRemotePlaceholders()
        let clip = NewClip(
            kind: .other,
            preview: ClipPreview(title: ""),
            representations: [],
            // Unique: placeholders are never merged with anything.
            fingerprintSource: Data("remote:\(UUID().uuidString)".utf8),
            origin: .remoteDevice,
            localOnly: true
        )
        let item = try store.save(clip).item
        remotePlaceholders[item.id] = changeCount
        return item
    }

    /// The pasteboard change a placeholder stands for, if it is still a placeholder.
    public func remotePlaceholderChangeCount(_ id: UUID) -> Int? {
        remotePlaceholders[id]
    }

    /// Placeholders are only useful while their copy is on the pasteboard; a newer
    /// change makes them unreachable, so they go.
    public func pasteboardDidChange(to changeCount: Int) {
        let stale = remotePlaceholders.filter { $0.value != changeCount }.map(\.key)
        guard !stale.isEmpty else { return }
        try? store.delete(stale)
        for id in stale {
            remotePlaceholders[id] = nil
        }
    }

    /// Replaces a placeholder with the content read on demand.
    public func materializeRemote(_ id: UUID, with content: CapturedContent) throws -> CaptureOutcome {
        remotePlaceholders[id] = nil
        try store.delete([id])
        var remote = content
        remote.origin = .remoteDevice
        return try capture(remote)
    }

    private func removeRemotePlaceholders() {
        guard !remotePlaceholders.isEmpty else { return }
        try? store.delete(Array(remotePlaceholders.keys))
        remotePlaceholders.removeAll()
    }

    // MARK: Reading

    public func snapshot(limit: Int? = nil) throws -> HistorySnapshot {
        HistorySnapshot(items: try store.items(limit: limit), favorites: try store.favorites())
    }

    public func representations(of id: UUID) throws -> [ClipRepresentation] {
        try store.representations(of: id)
    }

    // MARK: Changing

    @discardableResult
    public func markUsed(_ id: UUID) throws -> ClipItem? {
        try store.markUsed(id)
    }

    public func togglePin(_ id: UUID) throws {
        guard let item = try store.item(id: id) else { return }
        if item.isPinned {
            let expiry = HistoryRules.expiry(for: item.sensitivity, policy: policy.retention, now: timeSource.now())
            try store.unpin(id, expiresAt: expiry)
        } else {
            try store.pin(id)
        }
    }

    public func setPinLabel(_ id: UUID, label: String?) throws {
        try store.setPinLabel(id, label: label)
    }

    public func reorderFavorites(_ ids: [UUID]) throws {
        try store.reorderFavorites(ids)
    }

    public func clearSensitivity(_ id: UUID) throws {
        try store.clearSensitivity(id)
    }

    public func delete(_ ids: [UUID]) throws {
        for id in ids {
            remotePlaceholders[id] = nil
        }
        try store.delete(ids)
    }

    public func deleteAll(includingFavorites: Bool = false) throws {
        remotePlaceholders.removeAll()
        try store.deleteAll(includingFavorites: includingFavorites)
    }

    // MARK: Maintenance

    /// Retention plus orphan cleanup; returns the removed entries.
    @discardableResult
    public func runMaintenance() throws -> [UUID] {
        let removed = try store.applyRetention(policy.retention)
        try store.removeOrphans()
        return removed
    }

    /// Removes expired entries only (cheap; run when the next expiry is due).
    @discardableResult
    public func removeExpired() throws -> [UUID] {
        try store.applyRetention(policy.retention)
    }

    public func nextExpiry() throws -> Date? {
        try store.nextExpiry()
    }
}
