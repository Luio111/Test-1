import CopyPalCore
import Foundation
import Testing
@testable import CopyPalStorage

/// A fresh store in its own temporary directory.
struct StoreFixture {
    let directory: URL
    let keyStore: InMemoryKeyStore
    let time: OffsetTimeSource
    let store: ClipStore

    init(policyTime: OffsetTimeSource = OffsetTimeSource()) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyPalTests-\(UUID().uuidString)", isDirectory: true)
        keyStore = InMemoryKeyStore()
        time = policyTime
        store = try ClipStore.open(directory: directory, keyStore: keyStore, timeSource: time)
    }

    func reopen(keyStore: some KeyStore) throws -> ClipStore {
        try ClipStore.open(directory: directory, keyStore: keyStore, timeSource: time)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

func textClip(_ text: String, rtf: Bool = false, sensitivity: Sensitivity? = nil, expiresAt: Date? = nil) -> NewClip {
    var representations = [ClipRepresentation(type: PasteboardTypeID.plainText, data: Data(text.utf8))]
    if rtf {
        representations.append(ClipRepresentation(type: PasteboardTypeID.rtf, data: Data("{\\rtf1 \(text)}".utf8)))
    }
    return NewClip(
        kind: rtf ? .richText : .text,
        preview: ClipPreview(title: text, searchText: text.lowercased()),
        representations: representations,
        fingerprintSource: Data(("text:" + text).utf8),
        sourceBundleID: "com.apple.TextEdit",
        sensitivity: sensitivity,
        expiresAt: expiresAt
    )
}

@Suite(.serialized)
struct ClipStoreTests {
    @Test func insertAndReadBack() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.store.outcome == .created)

        let result = try fixture.store.save(textClip("Hallo", rtf: true))
        guard case let .inserted(item) = result else {
            Issue.record("expected insert, got \(result)")
            return
        }
        #expect(item.preview.title == "Hallo")
        #expect(item.kind == .richText)
        #expect(item.sourceBundleID == "com.apple.TextEdit")

        let representations = try fixture.store.representations(of: item.id)
        #expect(representations.map(\.type) == [PasteboardTypeID.plainText, PasteboardTypeID.rtf])
        #expect(representations.first?.data == Data("Hallo".utf8))
        #expect(try fixture.store.count() == 1)
    }

    @Test func newestFirst() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        for text in ["eins", "zwei", "drei"] {
            try fixture.store.save(textClip(text))
        }
        #expect(try fixture.store.items().map(\.preview.title) == ["drei", "zwei", "eins"])
        #expect(try fixture.store.items(limit: 2).map(\.preview.title) == ["drei", "zwei"])
    }

    @Test func duplicateOfTopChangesNothing() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let first = try fixture.store.save(textClip("gleich")).item
        let second = try fixture.store.save(textClip("gleich"))
        #expect(second == .unchanged(first))
        #expect(try fixture.store.count() == 1)
    }

    @Test func duplicateOfOlderMovesToTopWithNewFormats() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let original = try fixture.store.save(textClip("Rechnung")).item
        try fixture.store.save(textClip("anderes"))
        let result = try fixture.store.save(textClip("Rechnung", rtf: true))
        guard case let .movedToTop(moved) = result else {
            Issue.record("expected move, got \(result)")
            return
        }
        #expect(moved.id == original.id)
        #expect(moved.kind == .richText)
        #expect(try fixture.store.items().map(\.preview.title) == ["Rechnung", "anderes"])
        #expect(try fixture.store.representations(of: moved.id).count == 2)
        #expect(try fixture.store.count() == 2)
    }

    @Test func largeRepresentationsGoToEncryptedBlobs() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let big = String(repeating: "Geheimtext ", count: 20_000) // ~220 KB
        let item = try fixture.store.save(textClip(big)).item
        #expect(try fixture.store.representations(of: item.id).first?.data == Data(big.utf8))
        let blobFiles = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.appendingPathComponent("Blobs").path)
        #expect(blobFiles.count == 1)
    }

    @Test func nothingReadableOnDisk() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let marker = "UnverwechselbaresWort4711"
        try fixture.store.save(textClip("Text mit \(marker) drin"))
        try fixture.store.save(textClip(String(repeating: "\(marker) ", count: 10_000)))
        try fixture.store.pin(try #require(fixture.store.items().first).id, label: "Label \(marker)")

        let enumerator = try #require(FileManager.default.enumerator(at: fixture.directory, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            let bytes = try Data(contentsOf: url)
            #expect(bytes.range(of: Data(marker.utf8)) == nil, "Klartext in \(url.lastPathComponent)")
            checked += 1
        }
        #expect(checked >= 2)
    }

    @Test func survivesReopen() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        try fixture.store.save(textClip("bleibt"))
        let reopened = try fixture.reopen(keyStore: fixture.keyStore)
        #expect(reopened.outcome == .opened)
        #expect(try reopened.items().map(\.preview.title) == ["bleibt"])
    }

    @Test func lostKeyStartsFreshAndKeepsOldDataAside() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        try fixture.store.save(textClip("alt"))
        let reopened = try fixture.reopen(keyStore: InMemoryKeyStore())
        guard case let .recoveredFromKeyLoss(movedTo) = reopened.outcome else {
            Issue.record("expected recovery, got \(reopened.outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: movedTo.appendingPathComponent(ClipStore.databaseFileName).path))
        #expect(try reopened.count() == 0)
        try reopened.save(textClip("neu"))
        #expect(try reopened.items().map(\.preview.title) == ["neu"])
        try? FileManager.default.removeItem(at: movedTo)
    }

    @Test func wrongKeyStartsFresh() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        try fixture.store.save(textClip("alt"))
        let other = InMemoryKeyStore(key: StorageKey.generate())
        let reopened = try fixture.reopen(keyStore: other)
        guard case let .recoveredFromKeyLoss(movedTo) = reopened.outcome else {
            Issue.record("expected recovery, got \(reopened.outcome)")
            return
        }
        #expect(try reopened.count() == 0)
        try? FileManager.default.removeItem(at: movedTo)
    }

    @Test func tamperedPreviewIsDetected() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let item = try fixture.store.save(textClip("echt")).item
        try fixture.store.save(textClip("anderer"))
        try fixture.store.tamperPreviewForTesting(item.id)
        #expect(throws: StorageError.decryptionFailed) { try fixture.store.item(id: item.id) }
        #expect(try fixture.store.items().map(\.preview.title) == ["anderer"])
    }

    @Test func markUsedMovesToTopAndCounts() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let first = try fixture.store.save(textClip("eins")).item
        try fixture.store.save(textClip("zwei"))
        let used = try #require(try fixture.store.markUsed(first.id))
        #expect(used.useCount == 1)
        #expect(try fixture.store.items().map(\.preview.title) == ["eins", "zwei"])
    }

    @Test func favorites() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let a = try fixture.store.save(textClip("a")).item
        let b = try fixture.store.save(textClip("b")).item
        let c = try fixture.store.save(textClip("c", sensitivity: .iban, expiresAt: Date().addingTimeInterval(60))).item
        try fixture.store.pin(a.id, label: "Erster")
        try fixture.store.pin(c.id)
        try fixture.store.pin(b.id)
        #expect(try fixture.store.favorites().map(\.preview.title) == ["a", "c", "b"])
        #expect(try fixture.store.item(id: a.id)?.pinLabel == "Erster")
        #expect(try fixture.store.item(id: c.id)?.expiresAt == nil)

        try fixture.store.reorderFavorites([b.id, a.id, c.id])
        #expect(try fixture.store.favorites().map(\.preview.title) == ["b", "a", "c"])

        try fixture.store.setPinLabel(b.id, label: "Neu")
        #expect(try fixture.store.item(id: b.id)?.pinLabel == "Neu")

        try fixture.store.unpin(a.id)
        #expect(try fixture.store.favorites().map(\.preview.title) == ["b", "c"])
        #expect(try fixture.store.item(id: a.id)?.pinLabel == nil)
    }

    @Test func deleteAllKeepsFavoritesAndRemovesBlobs() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let big = try fixture.store.save(textClip(String(repeating: "x", count: 100_000))).item
        let favorite = try fixture.store.save(textClip("Favorit")).item
        try fixture.store.pin(favorite.id)
        #expect(!big.preview.title.isEmpty)

        try fixture.store.deleteAll()
        #expect(try fixture.store.items().map(\.preview.title) == ["Favorit"])
        let blobs = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.appendingPathComponent("Blobs").path)
        #expect(blobs.isEmpty)

        try fixture.store.deleteAll(includingFavorites: true)
        #expect(try fixture.store.count() == 0)
    }

    @Test func deletedContentCanBeCopiedAgain() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        let item = try fixture.store.save(textClip("weg")).item
        try fixture.store.delete([item.id])
        #expect(try fixture.store.item(id: item.id) == nil)
        let again = try fixture.store.save(textClip("weg"))
        guard case .inserted = again else {
            Issue.record("expected new entry, got \(again)")
            return
        }
    }

    @Test func retentionAndExpiry() throws {
        let time = OffsetTimeSource()
        let fixture = try StoreFixture(policyTime: time)
        defer { fixture.cleanUp() }
        try fixture.store.save(textClip("normal"))
        try fixture.store.save(textClip("DE89", sensitivity: .iban, expiresAt: time.now().addingTimeInterval(60)))
        let favorite = try fixture.store.save(textClip("Favorit")).item
        try fixture.store.pin(favorite.id)
        #expect(try fixture.store.nextExpiry() != nil)

        time.advance(by: 61)
        #expect(try fixture.store.applyRetention(.standard).count == 1)
        #expect(try fixture.store.items().map(\.preview.title) == ["Favorit", "normal"])

        time.advance(by: 2 * 86_400)
        try fixture.store.applyRetention(RetentionPolicy(maxAge: 86_400))
        #expect(try fixture.store.items().map(\.preview.title) == ["Favorit"])
    }

    @Test func clearSensitivity() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        var clip = textClip("4242 4242 4242 4242", sensitivity: .card, expiresAt: Date().addingTimeInterval(60))
        clip.preview.masked = "•••• 4242"
        let item = try fixture.store.save(clip).item
        #expect(item.displayTitle == "•••• 4242")
        try fixture.store.clearSensitivity(item.id)
        let cleared = try #require(try fixture.store.item(id: item.id))
        #expect(cleared.sensitivity == nil)
        #expect(cleared.expiresAt == nil)
        #expect(cleared.displayTitle == "4242 4242 4242 4242")
    }

    @Test func orphanBlobsAndOldTombstonesAreRemoved() throws {
        let time = OffsetTimeSource()
        let fixture = try StoreFixture(policyTime: time)
        defer { fixture.cleanUp() }
        let item = try fixture.store.save(textClip("kurz")).item
        try fixture.store.delete([item.id])
        let stray = fixture.directory.appendingPathComponent("Blobs").appendingPathComponent(UUID().uuidString + ".blob")
        try Data("x".utf8).write(to: stray)

        #expect(try fixture.store.removeOrphans() == 1)
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        #expect(try fixture.store.tombstoneCountForTesting() == 1)
        time.advance(by: 31 * 86_400)
        try fixture.store.removeOrphans()
        #expect(try fixture.store.tombstoneCountForTesting() == 0)
    }
}

@Suite(.serialized)
struct ThumbnailCacheTests {
    @Test func storedEncryptedAndRemovedWithItem() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("CopyPalThumbs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try ClipStore.open(
            directory: base.appendingPathComponent("Data"),
            thumbnailDirectory: base.appendingPathComponent("Thumbnails"),
            keyStore: InMemoryKeyStore()
        )
        let item = try store.save(textClip("Bild")).item
        let marker = Data("ThumbnailBytes4711".utf8)
        store.storeThumbnail(marker, for: item.id)
        #expect(store.thumbnail(for: item.id) == marker)

        let file = base.appendingPathComponent("Thumbnails").appendingPathComponent(item.id.uuidString + ".blob")
        let onDisk = try Data(contentsOf: file)
        #expect(onDisk.range(of: marker) == nil)

        try store.delete([item.id])
        #expect(store.thumbnail(for: item.id) == nil)

        store.storeThumbnail(marker, for: UUID())
        #expect(try store.removeOrphans() == 1)
    }
}
