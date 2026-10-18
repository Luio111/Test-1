import CopyPalCore
import CopyPalStorage
import Foundation
import Testing
@testable import CopyPalServices

struct EngineFixture {
    let directory: URL
    let time: OffsetTimeSource
    let engine: HistoryEngine

    init(policy: CapturePolicy = CapturePolicy()) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CopyPalEngine-\(UUID().uuidString)")
        time = OffsetTimeSource()
        let store = try ClipStore.open(directory: directory, keyStore: InMemoryKeyStore(), timeSource: time)
        engine = HistoryEngine(store: store, policy: policy, timeSource: time)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

func copied(_ text: String, rtf: Bool = false, source: String? = "com.apple.TextEdit", origin: ClipOrigin = .local) -> CapturedContent {
    var representations = [ClipRepresentation(type: PasteboardTypeID.plainText, data: Data(text.utf8))]
    if rtf {
        representations.append(ClipRepresentation(type: PasteboardTypeID.rtf, data: Data("{\\rtf1\\b \(text)}".utf8)))
    }
    representations.append(ClipRepresentation(type: "com.example.private-format", data: Data(repeating: 1, count: 100)))
    return CapturedContent(representations: representations, sourceBundleID: source, origin: origin)
}

/// A screenshot as the screenshot writer hands it over (the PNG header is enough).
func screenshot(_ caption: String?, salt: UInt8 = 0) -> CapturedContent {
    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
    png.append(contentsOf: [0, 0, 3, 0x20, 0, 0, 2, 0x58, salt])
    return CapturedContent(
        representations: [ClipRepresentation(type: PasteboardTypeID.png, data: png)],
        sourceBundleID: "com.apple.Safari",
        hints: ContentHints(capturedFrom: caption)
    )
}

@Suite(.serialized)
struct HistoryEngineTests {
    @Test func recognizedTextMakesImagesSearchable() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        guard case let .stored(result) = try await fixture.engine.capture(screenshot("Safari – Rechnung")) else {
            Issue.record("not stored")
            return
        }
        #expect(try await fixture.engine.imagesAwaitingTextRecognition(limit: 10) == [result.item.id])
        let found = try await fixture.engine.applyRecognizedText(result.item.id, text: "Rechnungsnummer 2026-118\nBetrag 49,00 €")
        #expect(found == nil)
        let item = try #require(try await fixture.engine.snapshot().items.first)
        #expect(item.preview.searchText == "safari – rechnung rechnungsnummer 2026-118 betrag 49,00 €")
        #expect(item.preview.textRecognized == true)
        #expect(item.sensitivity == nil)
        #expect(try await fixture.engine.imagesAwaitingTextRecognition(limit: 10).isEmpty)
        // Once per image.
        #expect(try await fixture.engine.applyRecognizedText(result.item.id, text: "DE89 3704 0044 0532 0130 00") == nil)
    }

    @Test func sensitiveTextInAnImageMakesItSensitive() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        guard case let .stored(result) = try await fixture.engine.capture(screenshot("Banking")) else {
            Issue.record("not stored")
            return
        }
        let found = try await fixture.engine.applyRecognizedText(result.item.id, text: "IBAN DE89 3704 0044 0532 0130 00")
        #expect(found == .iban)
        let item = try #require(try await fixture.engine.snapshot().items.first)
        #expect(item.sensitivity == .iban)
        #expect(item.localOnly)
        #expect(item.preview.searchText.isEmpty)
        #expect(item.expiresAt != nil)
        fixture.time.advance(by: 61)
        try await fixture.engine.removeExpired()
        #expect(try await fixture.engine.snapshot().items.isEmpty)
    }

    @Test func imagesWithoutTextAreMarkedDone() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        guard case let .stored(result) = try await fixture.engine.capture(screenshot(nil, salt: 1)) else {
            Issue.record("not stored")
            return
        }
        try await fixture.engine.applyRecognizedText(result.item.id, text: nil)
        #expect(try await fixture.engine.imagesAwaitingTextRecognition(limit: 10).isEmpty)
        let item = try #require(try await fixture.engine.snapshot().items.first)
        #expect(item.preview.searchText.isEmpty)
    }

    @Test func deletedImagesAreLeftAlone() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        guard case let .stored(result) = try await fixture.engine.capture(screenshot("Weg", salt: 2)) else {
            Issue.record("not stored")
            return
        }
        try await fixture.engine.delete([result.item.id])
        #expect(try await fixture.engine.applyRecognizedText(result.item.id, text: "DE89 3704 0044 0532 0130 00") == nil)
        #expect(try await fixture.engine.snapshot().items.isEmpty)
    }

    @Test func capturesInOrder() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        for index in 1...10 {
            _ = try await fixture.engine.capture(copied("Text \(index)"))
        }
        let snapshot = try await fixture.engine.snapshot(limit: 8)
        #expect(snapshot.items.map(\.preview.title) == (3...10).reversed().map { "Text \($0)" })
    }

    @Test func storesOnlyKnownFormats() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        let outcome = try await fixture.engine.capture(copied("Fett", rtf: true))
        guard case let .stored(result) = outcome else {
            Issue.record("not stored: \(outcome)")
            return
        }
        let types = try await fixture.engine.representations(of: result.item.id).map(\.type)
        #expect(types == [PasteboardTypeID.plainText, PasteboardTypeID.rtf])
        #expect(result.item.kind == .richText)
    }

    @Test func duplicatesMoveUp() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        _ = try await fixture.engine.capture(copied("A"))
        _ = try await fixture.engine.capture(copied("B"))
        _ = try await fixture.engine.capture(copied("A"))
        let titles = try await fixture.engine.snapshot().items.map(\.preview.title)
        #expect(titles == ["A", "B"])
    }

    @Test func sensitiveIsMaskedLocalOnlyAndExpires() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        let outcome = try await fixture.engine.capture(copied("DE89 3704 0044 0532 0130 00"))
        guard case let .stored(result) = outcome else {
            Issue.record("not stored: \(outcome)")
            return
        }
        #expect(result.item.sensitivity == .iban)
        #expect(result.item.displayTitle == "DE89 •••• 3000")
        #expect(result.item.preview.searchText.isEmpty)
        #expect(result.item.localOnly)
        #expect(result.item.expiresAt != nil)

        fixture.time.advance(by: 61)
        let removed = try await fixture.engine.removeExpired()
        #expect(removed == [result.item.id])
        #expect(try await fixture.engine.snapshot().items.isEmpty)
    }

    @Test func pinnedSensitiveDoesNotExpire() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        guard case let .stored(result) = try await fixture.engine.capture(copied("4242 4242 4242 4242")) else {
            Issue.record("not stored")
            return
        }
        try await fixture.engine.togglePin(result.item.id)
        fixture.time.advance(by: 3_600)
        try await fixture.engine.removeExpired()
        #expect(try await fixture.engine.snapshot().favorites.count == 1)

        try await fixture.engine.togglePin(result.item.id)
        fixture.time.advance(by: 61)
        try await fixture.engine.removeExpired()
        #expect(try await fixture.engine.snapshot().items.isEmpty)
    }

    @Test func tooLargeIsSkipped() async throws {
        let fixture = try EngineFixture(policy: CapturePolicy(retention: RetentionPolicy(maxTextBytes: 10)))
        defer { fixture.cleanUp() }
        let outcome = try await fixture.engine.capture(copied("deutlich mehr als zehn Bytes"))
        #expect(outcome == .skipped(.tooLarge))
    }

    @Test func historyLimit() async throws {
        let fixture = try EngineFixture(policy: CapturePolicy(retention: RetentionPolicy(maxItems: 3)))
        defer { fixture.cleanUp() }
        for index in 1...5 {
            _ = try await fixture.engine.capture(copied("\(index)"))
        }
        #expect(try await fixture.engine.snapshot().items.map(\.preview.title) == ["5", "4", "3"])
    }

    @Test func remotePlaceholderLifecycle() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        let placeholder = try await fixture.engine.recordRemotePlaceholder(changeCount: 7)
        #expect(placeholder.origin == .remoteDevice)
        #expect(await fixture.engine.remotePlaceholderChangeCount(placeholder.id) == 7)

        let outcome = try await fixture.engine.materializeRemote(placeholder.id, with: copied("vom iPhone", source: nil))
        guard case let .stored(result) = outcome else {
            Issue.record("not stored: \(outcome)")
            return
        }
        #expect(result.item.origin == .remoteDevice)
        #expect(result.item.localOnly)
        let titles = try await fixture.engine.snapshot().items.map(\.preview.title)
        #expect(titles == ["vom iPhone"])
    }

    @Test func stalePlaceholderIsRemoved() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        _ = try await fixture.engine.recordRemotePlaceholder(changeCount: 7)
        await fixture.engine.pasteboardDidChange(to: 7)
        #expect(try await fixture.engine.snapshot().items.count == 1)
        await fixture.engine.pasteboardDidChange(to: 8)
        #expect(try await fixture.engine.snapshot().items.isEmpty)
    }

    @Test func clearHistoryKeepsFavorites() async throws {
        let fixture = try EngineFixture()
        defer { fixture.cleanUp() }
        guard case let .stored(keep) = try await fixture.engine.capture(copied("Favorit")) else { return }
        _ = try await fixture.engine.capture(copied("weg"))
        try await fixture.engine.togglePin(keep.item.id)
        try await fixture.engine.deleteAll()
        #expect(try await fixture.engine.snapshot().items.map(\.preview.title) == ["Favorit"])
    }
}
