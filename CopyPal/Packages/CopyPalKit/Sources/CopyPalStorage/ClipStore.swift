import CopyPalCore
import Foundation
import GRDB

/// A copy ready to be stored (classified, checked for sensitive content).
public struct NewClip: Sendable, Equatable {
    public var kind: ClipKind
    public var preview: ClipPreview
    public var representations: [ClipRepresentation]
    /// Canonical content for duplicate detection; stored only as an HMAC.
    public var fingerprintSource: Data
    public var sourceBundleID: String?
    public var origin: ClipOrigin
    public var sensitivity: Sensitivity?
    public var expiresAt: Date?
    public var localOnly: Bool

    public init(
        kind: ClipKind,
        preview: ClipPreview,
        representations: [ClipRepresentation],
        fingerprintSource: Data,
        sourceBundleID: String? = nil,
        origin: ClipOrigin = .local,
        sensitivity: Sensitivity? = nil,
        expiresAt: Date? = nil,
        localOnly: Bool = false
    ) {
        self.kind = kind
        self.preview = preview
        self.representations = representations
        self.fingerprintSource = fingerprintSource
        self.sourceBundleID = sourceBundleID
        self.origin = origin
        self.sensitivity = sensitivity
        self.expiresAt = expiresAt
        self.localOnly = localOnly
    }

    public var byteSize: Int {
        representations.reduce(0) { $0 + $1.data.count }
    }
}

public enum SaveResult: Sendable, Equatable {
    case inserted(ClipItem)
    /// Same content as an older entry: that entry moved to the top (with the new formats).
    case movedToTop(ClipItem)
    /// Same content as the newest entry: nothing changed.
    case unchanged(ClipItem)

    public var item: ClipItem {
        switch self {
        case let .inserted(item), let .movedToTop(item), let .unchanged(item): item
        }
    }
}

public enum OpenOutcome: Sendable, Equatable {
    case created
    case opened
    /// The key was missing or did not fit the data (e.g. after changing the signing
    /// team): the unreadable data was moved to `movedTo` and a new history started.
    case recoveredFromKeyLoss(movedTo: URL)
}

/// The encrypted history on disk: SQLite (WAL) plus encrypted blob files.
/// Thread-safe; writes are serialized by the database.
public final class ClipStore: Sendable {
    public static let databaseFileName = "History.sqlite"
    /// Representations up to this size stay in the database, larger ones go to files.
    static let inlineLimit = 64 * 1024

    public let directory: URL
    public let outcome: OpenOutcome
    private let pool: DatabasePool
    private let cipher: FieldCipher
    private let blobs: BlobStore
    /// Encrypted image thumbnails (a cache: may be deleted any time).
    private let thumbnails: BlobStore?
    private let timeSource: any TimeSource

    private init(
        directory: URL,
        outcome: OpenOutcome,
        pool: DatabasePool,
        cipher: FieldCipher,
        blobs: BlobStore,
        thumbnails: BlobStore?,
        timeSource: any TimeSource
    ) {
        self.directory = directory
        self.outcome = outcome
        self.pool = pool
        self.cipher = cipher
        self.blobs = blobs
        self.thumbnails = thumbnails
        self.timeSource = timeSource
    }

    // MARK: Opening

    /// Opens (or creates) the history in `directory`. Never fails because of a lost or
    /// wrong key: the old data is moved aside instead (`OpenOutcome.recoveredFromKeyLoss`).
    public static func open(
        directory: URL,
        thumbnailDirectory: URL? = nil,
        keyStore: some KeyStore,
        timeSource: any TimeSource = SystemTimeSource()
    ) throws -> ClipStore {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent(databaseFileName)
        var outcome: OpenOutcome = fileManager.fileExists(atPath: databaseURL.path) ? .opened : .created

        let key: StorageKey
        if let stored = try keyStore.loadKey() {
            key = stored
        } else {
            if outcome == .opened {
                outcome = .recoveredFromKeyLoss(movedTo: try moveAside(directory, now: timeSource.now()))
            }
            key = StorageKey.generate()
            try keyStore.saveKey(key)
        }

        let cipher = FieldCipher(key: key)
        var pool = try makePool(at: databaseURL)
        if outcome == .opened, try !keyMatches(pool, cipher: cipher) {
            try pool.close()
            outcome = .recoveredFromKeyLoss(movedTo: try moveAside(directory, now: timeSource.now()))
            pool = try makePool(at: databaseURL)
        }
        try storeKeyCheckIfMissing(pool, cipher: cipher)

        let blobs = try BlobStore(directory: directory.appendingPathComponent("Blobs", isDirectory: true), cipher: cipher)
        if case .recoveredFromKeyLoss = outcome, let thumbnailDirectory {
            // Thumbnails made with the old key cannot be read anymore.
            try? FileManager.default.removeItem(at: thumbnailDirectory)
        }
        let thumbnails = try thumbnailDirectory.map { try BlobStore(directory: $0, cipher: cipher) }
        return ClipStore(
            directory: directory,
            outcome: outcome,
            pool: pool,
            cipher: cipher,
            blobs: blobs,
            thumbnails: thumbnails,
            timeSource: timeSource
        )
    }

    private static func makePool(at url: URL) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.label = "CopyPal.History"
        configuration.prepareDatabase { db in
            // WAL + NORMAL: durable across app crashes, fast inserts.
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        try Schema.migrator.migrate(pool)
        return pool
    }

    private static let keyCheckContext = "meta:key_check"
    private static let keyCheckPlaintext = Data("CopyPal key check".utf8)

    private static func keyMatches(_ pool: DatabasePool, cipher: FieldCipher) throws -> Bool {
        guard let sealed = try pool.read({ try Data.fetchOne($0, sql: "SELECT value FROM meta WHERE key = 'key_check'") }) else {
            return true
        }
        return (try? cipher.open(sealed, context: keyCheckContext)) == keyCheckPlaintext
    }

    private static func storeKeyCheckIfMissing(_ pool: DatabasePool, cipher: FieldCipher) throws {
        let sealed = try cipher.seal(keyCheckPlaintext, context: keyCheckContext)
        try pool.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO meta (key, value) VALUES ('key_check', ?)", arguments: [sealed])
        }
    }

    /// "…/<bundle-id>" → "…/<bundle-id> (unlesbar 2026-10-12 14-03-22)", then an empty
    /// directory in its place.
    private static func moveAside(_ directory: URL, now: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = "\(directory.lastPathComponent) (unlesbar \(formatter.string(from: now)))"
        let destination = directory.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.moveItem(at: directory, to: destination)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return destination
    }

    // MARK: Saving

    /// Stores a copy: same content as the newest entry → nothing; same as an older
    /// entry → that entry moves to the top with the new formats; otherwise a new entry.
    @discardableResult
    public func save(_ new: NewClip) throws -> SaveResult {
        let now = timeSource.now()
        let fingerprint = cipher.fingerprint(new.fingerprintSource)
        var writtenBlobs: [UUID] = []
        var replacedBlobs: [UUID] = []
        do {
            let result = try pool.write { db -> SaveResult in
                let existingID = try String.fetchOne(
                    db,
                    sql: "SELECT id FROM clip_item WHERE deleted_at IS NULL AND fingerprint = ? ORDER BY last_used_at DESC LIMIT 1",
                    arguments: [fingerprint]
                )
                guard let existingID, let id = UUID(uuidString: existingID) else {
                    let id = UUID()
                    try insertItem(db, id: id, new: new, fingerprint: fingerprint, now: now)
                    writtenBlobs += try insertRepresentations(db, itemID: id, representations: new.representations)
                    return .inserted(try fetchItem(db, id: id))
                }

                let topID = try String.fetchOne(db, sql: "SELECT id FROM clip_item WHERE deleted_at IS NULL ORDER BY last_used_at DESC LIMIT 1")
                if topID == existingID {
                    return .unchanged(try fetchItem(db, id: id))
                }
                replacedBlobs += try deleteRepresentations(db, itemID: id)
                let isPinned = try Bool.fetchOne(db, sql: "SELECT pinned_at IS NOT NULL FROM clip_item WHERE id = ?", arguments: [existingID]) ?? false
                try db.execute(
                    sql: """
                    UPDATE clip_item SET last_used_at = ?, modified_at = ?, kind = ?, preview_enc = ?, source_bundle_id = ?,
                        origin = ?, sensitivity = ?, expires_at = ?, local_only = ?, byte_size = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        now.timeIntervalSince1970, now.timeIntervalSince1970, new.kind.rawValue,
                        try sealPreview(new.preview, id: id), new.sourceBundleID, new.origin.rawValue,
                        new.sensitivity?.rawValue, isPinned ? nil : new.expiresAt?.timeIntervalSince1970,
                        new.localOnly, new.byteSize, existingID,
                    ]
                )
                writtenBlobs += try insertRepresentations(db, itemID: id, representations: new.representations)
                return .movedToTop(try fetchItem(db, id: id))
            }
            blobs.delete(replacedBlobs)
            return result
        } catch {
            blobs.delete(writtenBlobs)
            throw error
        }
    }

    private func insertItem(_ db: Database, id: UUID, new: NewClip, fingerprint: Data, now: Date) throws {
        try db.execute(
            sql: """
            INSERT INTO clip_item (id, created_at, last_used_at, modified_at, kind, fingerprint, preview_enc,
                source_bundle_id, origin, sensitivity, expires_at, local_only, byte_size, use_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
            arguments: [
                id.uuidString, now.timeIntervalSince1970, now.timeIntervalSince1970, now.timeIntervalSince1970,
                new.kind.rawValue, fingerprint, try sealPreview(new.preview, id: id), new.sourceBundleID,
                new.origin.rawValue, new.sensitivity?.rawValue, new.expiresAt?.timeIntervalSince1970,
                new.localOnly, new.byteSize,
            ]
        )
    }

    /// Returns the IDs of blob files written, so they can be removed if the
    /// transaction fails.
    private func insertRepresentations(_ db: Database, itemID: UUID, representations: [ClipRepresentation]) throws -> [UUID] {
        var written: [UUID] = []
        for (position, representation) in representations.enumerated() {
            let id = UUID()
            var inline: Data?
            var blobID: UUID?
            if representation.data.count > Self.inlineLimit {
                let blob = try blobs.write(representation.data)
                written.append(blob)
                blobID = blob
            } else {
                inline = try cipher.seal(representation.data, context: Self.representationContext(id))
            }
            try db.execute(
                sql: """
                INSERT INTO clip_representation (id, item_id, item_index, position, uti, data_enc, blob_id, byte_size)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id.uuidString, itemID.uuidString, representation.item, position, representation.type,
                    inline, blobID?.uuidString, representation.data.count,
                ]
            )
        }
        return written
    }

    /// Deletes an item's representations; returns the blob files to remove after commit.
    private func deleteRepresentations(_ db: Database, itemID: UUID) throws -> [UUID] {
        let blobIDs = try String.fetchAll(
            db,
            sql: "SELECT blob_id FROM clip_representation WHERE item_id = ? AND blob_id IS NOT NULL",
            arguments: [itemID.uuidString]
        )
        try db.execute(sql: "DELETE FROM clip_representation WHERE item_id = ?", arguments: [itemID.uuidString])
        return blobIDs.compactMap(UUID.init(uuidString:))
    }

    // MARK: Reading

    /// Newest first. Entries that cannot be decrypted (tampered with) are left out.
    public func items(limit: Int? = nil) throws -> [ClipItem] {
        try pool.read { db in
            var sql = "SELECT * FROM clip_item WHERE deleted_at IS NULL ORDER BY last_used_at DESC"
            if let limit { sql += " LIMIT \(max(limit, 0))" }
            return try Row.fetchAll(db, sql: sql).compactMap { try? decodeItem($0) }
        }
    }

    /// Favorites in their user-defined order.
    public func favorites() throws -> [ClipItem] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM clip_item WHERE deleted_at IS NULL AND pinned_at IS NOT NULL ORDER BY pin_sort, pinned_at"
            ).compactMap { try? decodeItem($0) }
        }
    }

    public func item(id: UUID) throws -> ClipItem? {
        try pool.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM clip_item WHERE id = ? AND deleted_at IS NULL", arguments: [id.uuidString])
                .map(decodeItem)
        }
    }

    public func count() throws -> Int {
        try pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clip_item WHERE deleted_at IS NULL") ?? 0 }
    }

    /// The stored pasteboard representations, decrypted, in their original order.
    public func representations(of id: UUID) throws -> [ClipRepresentation] {
        let rows = try pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, item_index, uti, data_enc, blob_id FROM clip_representation WHERE item_id = ? ORDER BY position",
                arguments: [id.uuidString]
            )
        }
        return try rows.map { row in
            let representationID: String = row["id"]
            let data: Data
            if let blobID = (row["blob_id"] as String?).flatMap(UUID.init(uuidString:)) {
                data = try blobs.read(blobID)
            } else if let sealed: Data = row["data_enc"], let uuid = UUID(uuidString: representationID) {
                data = try cipher.open(sealed, context: Self.representationContext(uuid))
            } else {
                throw StorageError.notFound
            }
            return ClipRepresentation(item: row["item_index"], type: row["uti"], data: data)
        }
    }

    private func fetchItem(_ db: Database, id: UUID) throws -> ClipItem {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM clip_item WHERE id = ?", arguments: [id.uuidString]) else {
            throw StorageError.notFound
        }
        return try decodeItem(row)
    }

    private func decodeItem(_ row: Row) throws -> ClipItem {
        guard let id = UUID(uuidString: row["id"]) else { throw StorageError.notFound }
        let preview: ClipPreview = if let sealed: Data = row["preview_enc"] {
            try JSONDecoder().decode(ClipPreview.self, from: cipher.open(sealed, context: Self.previewContext(id)))
        } else {
            ClipPreview(title: "")
        }
        let pinLabel: String? = if let sealed: Data = row["pin_label_enc"] {
            String(data: try cipher.open(sealed, context: Self.pinLabelContext(id)), encoding: .utf8)
        } else {
            nil
        }
        return ClipItem(
            id: id,
            createdAt: Self.date(row["created_at"]) ?? .distantPast,
            lastUsedAt: Self.date(row["last_used_at"]),
            kind: ClipKind(rawValue: row["kind"]) ?? .other,
            preview: preview,
            sourceBundleID: row["source_bundle_id"],
            origin: ClipOrigin(rawValue: row["origin"]) ?? .local,
            sensitivity: (row["sensitivity"] as String?).flatMap(Sensitivity.init(rawValue:)),
            expiresAt: Self.date(row["expires_at"]),
            localOnly: row["local_only"],
            pinnedAt: Self.date(row["pinned_at"]),
            pinLabel: pinLabel,
            pinSort: row["pin_sort"],
            byteSize: row["byte_size"],
            useCount: row["use_count"]
        )
    }

    private static func date(_ value: Double?) -> Date? {
        value.map(Date.init(timeIntervalSince1970:))
    }

    // MARK: Changing

    /// Pasted from CopyPal: moves to the top and counts the use.
    @discardableResult
    public func markUsed(_ id: UUID) throws -> ClipItem? {
        let now = timeSource.now().timeIntervalSince1970
        return try pool.write { db in
            try db.execute(
                sql: "UPDATE clip_item SET last_used_at = ?, modified_at = ?, use_count = use_count + 1 WHERE id = ? AND deleted_at IS NULL",
                arguments: [now, now, id.uuidString]
            )
            return db.changesCount > 0 ? try fetchItem(db, id: id) : nil
        }
    }

    /// Makes an entry a favorite (at the end of the favorites). Favorites never expire.
    public func pin(_ id: UUID, label: String? = nil) throws {
        let now = timeSource.now().timeIntervalSince1970
        try pool.write { db in
            let maxSort = try Double.fetchOne(db, sql: "SELECT MAX(pin_sort) FROM clip_item WHERE pinned_at IS NOT NULL AND deleted_at IS NULL") ?? 0
            try db.execute(
                sql: """
                UPDATE clip_item SET pinned_at = ?, pin_sort = ?, pin_label_enc = ?, expires_at = NULL, modified_at = ?
                WHERE id = ? AND deleted_at IS NULL AND pinned_at IS NULL
                """,
                arguments: [now, maxSort + 1, try sealLabel(label, id: id), now, id.uuidString]
            )
        }
    }

    /// Removes an entry from the favorites; `expiresAt` restores a sensitive entry's expiry.
    public func unpin(_ id: UUID, expiresAt: Date? = nil) throws {
        let now = timeSource.now().timeIntervalSince1970
        try pool.write { db in
            try db.execute(
                sql: """
                UPDATE clip_item SET pinned_at = NULL, pin_sort = NULL, pin_label_enc = NULL, expires_at = ?, modified_at = ?
                WHERE id = ?
                """,
                arguments: [expiresAt?.timeIntervalSince1970, now, id.uuidString]
            )
        }
    }

    public func setPinLabel(_ id: UUID, label: String?) throws {
        let now = timeSource.now().timeIntervalSince1970
        try pool.write { db in
            try db.execute(
                sql: "UPDATE clip_item SET pin_label_enc = ?, modified_at = ? WHERE id = ? AND pinned_at IS NOT NULL",
                arguments: [try sealLabel(label, id: id), now, id.uuidString]
            )
        }
    }

    /// New order of the favorites (IDs not listed keep their place after these).
    public func reorderFavorites(_ ids: [UUID]) throws {
        try pool.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE clip_item SET pin_sort = ? WHERE id = ? AND pinned_at IS NOT NULL",
                    arguments: [Double(index + 1), id.uuidString]
                )
            }
        }
    }

    /// The text recognized in an image: the new search text; with sensitive content
    /// the entry turns sensitive (expires unless a favorite, stays on this Mac).
    /// Nothing happens when the entry was deleted meanwhile.
    public func applyRecognizedText(_ id: UUID, searchText: String, sensitivity: Sensitivity?, expiresAt: Date?) throws {
        let now = timeSource.now().timeIntervalSince1970
        try pool.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM clip_item WHERE id = ? AND deleted_at IS NULL", arguments: [id.uuidString]) else {
                return
            }
            var item = try decodeItem(row)
            item.preview.searchText = searchText
            item.preview.textRecognized = true
            if let sensitivity {
                try db.execute(
                    sql: """
                    UPDATE clip_item SET preview_enc = ?, sensitivity = ?, expires_at = ?, local_only = 1, modified_at = ?
                    WHERE id = ?
                    """,
                    arguments: [try sealPreview(item.preview, id: id), sensitivity.rawValue, expiresAt?.timeIntervalSince1970, now, id.uuidString]
                )
            } else {
                try db.execute(
                    sql: "UPDATE clip_item SET preview_enc = ?, modified_at = ? WHERE id = ?",
                    arguments: [try sealPreview(item.preview, id: id), now, id.uuidString]
                )
            }
        }
    }

    /// "Not sensitive": shows the content, makes it searchable and stops the expiry.
    public func clearSensitivity(_ id: UUID) throws {
        let now = timeSource.now().timeIntervalSince1970
        try pool.write { db in
            var item = try fetchItem(db, id: id)
            item.preview.masked = nil
            try db.execute(
                sql: "UPDATE clip_item SET sensitivity = NULL, expires_at = NULL, preview_enc = ?, modified_at = ? WHERE id = ?",
                arguments: [try sealPreview(item.preview, id: id), now, id.uuidString]
            )
        }
    }

    /// Deletes entries: content and blobs are removed at once, a tombstone with the ID
    /// stays (for sync later, ROADMAP §1.6).
    public func delete(_ ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let now = timeSource.now().timeIntervalSince1970
        var blobIDs: [UUID] = []
        try pool.write { db in
            for id in ids {
                blobIDs += try deleteRepresentations(db, itemID: id)
                try db.execute(
                    sql: """
                    UPDATE clip_item SET deleted_at = ?, modified_at = ?, preview_enc = NULL, fingerprint = NULL,
                        pinned_at = NULL, pin_sort = NULL, pin_label_enc = NULL, expires_at = NULL, byte_size = 0
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                    arguments: [now, now, id.uuidString]
                )
            }
        }
        blobs.delete(blobIDs)
        thumbnails?.delete(ids)
    }

    /// "Clear history": every entry except the favorites (unless `includingFavorites`).
    public func deleteAll(includingFavorites: Bool = false) throws {
        let ids = try pool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT id FROM clip_item WHERE deleted_at IS NULL" + (includingFavorites ? "" : " AND pinned_at IS NULL")
            )
        }
        try delete(ids.compactMap(UUID.init(uuidString:)))
    }

    // MARK: Cleanup

    /// Applies limits and expiry (`HistoryRules`); returns the removed IDs.
    @discardableResult
    public func applyRetention(_ policy: RetentionPolicy) throws -> [UUID] {
        let candidates = try pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, last_used_at, pinned_at, expires_at, byte_size FROM clip_item WHERE deleted_at IS NULL"
            ).compactMap { row -> RetentionCandidate? in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                return RetentionCandidate(
                    id: id,
                    lastUsedAt: Self.date(row["last_used_at"]) ?? .distantPast,
                    isPinned: (row["pinned_at"] as Double?) != nil,
                    expiresAt: Self.date(row["expires_at"]),
                    byteSize: row["byte_size"]
                )
            }
        }
        let removed = HistoryRules.itemsToRemove(candidates, policy: policy, now: timeSource.now())
        try delete(removed)
        return removed
    }

    /// The earliest expiry of a non-favorite entry, to schedule the next cleanup.
    public func nextExpiry() throws -> Date? {
        try pool.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT MIN(expires_at) FROM clip_item WHERE deleted_at IS NULL AND pinned_at IS NULL AND expires_at IS NOT NULL"
            ).map(Date.init(timeIntervalSince1970:))
        }
    }

    /// Deletes blob files no representation points to (left over after a crash) and
    /// tombstones older than `tombstoneAge`. Returns the number of files removed.
    @discardableResult
    public func removeOrphans(tombstoneAge: TimeInterval = 30 * 86_400) throws -> Int {
        let cutoff = timeSource.now().addingTimeInterval(-tombstoneAge).timeIntervalSince1970
        let orphans = try pool.write { db -> Set<UUID> in
            try db.execute(sql: "DELETE FROM clip_item WHERE deleted_at IS NOT NULL AND deleted_at < ?", arguments: [cutoff])
            let referenced = Set(
                try String.fetchAll(db, sql: "SELECT blob_id FROM clip_representation WHERE blob_id IS NOT NULL")
                    .compactMap(UUID.init(uuidString:))
            )
            return blobs.allIDs().subtracting(referenced)
        }
        blobs.delete(orphans)
        var removed = orphans.count
        if let thumbnails {
            let live = Set(try pool.read { db in
                try String.fetchAll(db, sql: "SELECT id FROM clip_item WHERE deleted_at IS NULL")
            }.compactMap(UUID.init(uuidString:)))
            let stale = thumbnails.allIDs().subtracting(live)
            thumbnails.delete(stale)
            removed += stale.count
        }
        return removed
    }

    // MARK: Thumbnails

    /// The cached thumbnail of an image entry, if one was stored.
    public func thumbnail(for id: UUID) -> Data? {
        try? thumbnails?.read(id)
    }

    public func storeThumbnail(_ data: Data, for id: UUID) {
        try? thumbnails?.write(data, id: id)
    }

    /// Bytes used on disk by the database and blob files.
    public func diskUsage() -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    // MARK: Test support

    /// Flips a byte of the stored preview (tamper-detection tests).
    func tamperPreviewForTesting(_ id: UUID) throws {
        try pool.write { db in
            guard var sealed = try Data.fetchOne(db, sql: "SELECT preview_enc FROM clip_item WHERE id = ?", arguments: [id.uuidString]) else {
                throw StorageError.notFound
            }
            sealed[sealed.startIndex + sealed.count / 2] ^= 0xFF
            try db.execute(sql: "UPDATE clip_item SET preview_enc = ? WHERE id = ?", arguments: [sealed, id.uuidString])
        }
    }

    func tombstoneCountForTesting() throws -> Int {
        try pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clip_item WHERE deleted_at IS NOT NULL") ?? 0 }
    }

    // MARK: Encryption contexts

    private func sealPreview(_ preview: ClipPreview, id: UUID) throws -> Data {
        try cipher.seal(JSONEncoder().encode(preview), context: Self.previewContext(id))
    }

    private func sealLabel(_ label: String?, id: UUID) throws -> Data? {
        guard let label, !label.isEmpty else { return nil }
        return try cipher.seal(Data(label.utf8), context: Self.pinLabelContext(id))
    }

    private static func previewContext(_ id: UUID) -> String { "item:\(id.uuidString):preview" }
    private static func pinLabelContext(_ id: UUID) -> String { "item:\(id.uuidString):pin_label" }
    private static func representationContext(_ id: UUID) -> String { "representation:\(id.uuidString)" }
}
