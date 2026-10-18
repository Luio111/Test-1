import Foundation
import Testing
@testable import CopyPalCore

struct ContentClassifierTests {
    private func text(_ string: String, extra: [ClipRepresentation] = []) -> CapturedContent {
        CapturedContent(representations: [ClipRepresentation(type: PasteboardTypeID.plainText, data: Data(string.utf8))] + extra)
    }

    @Test func plainText() throws {
        let result = try #require(ContentClassifier.classify(text("  Hallo Welt\nZweite Zeile\n")))
        #expect(result.kind == .text)
        #expect(result.preview.title == "Hallo Welt")
        #expect(result.preview.lineCount == 3)
        #expect(result.preview.isFormatted == false)
        #expect(result.text == "  Hallo Welt\nZweite Zeile\n")
    }

    @Test func richTextKeepsPlainFingerprint() throws {
        let plain = try #require(ContentClassifier.classify(text("Rechnung")))
        let rich = try #require(ContentClassifier.classify(text("Rechnung", extra: [
            ClipRepresentation(type: PasteboardTypeID.rtf, data: Data("{\\rtf1 Rechnung}".utf8)),
        ])))
        #expect(rich.kind == .richText)
        #expect(rich.preview.isFormatted)
        #expect(rich.fingerprintSource == plain.fingerprintSource)
    }

    @Test func link() throws {
        let result = try #require(ContentClassifier.classify(text("https://www.example.com/docs/a?b=1")))
        #expect(result.kind == .link)
        #expect(result.preview.link == LinkInfo(url: "https://www.example.com/docs/a?b=1", host: "example.com", path: "/docs/a?b=1"))
    }

    @Test func color() throws {
        let result = try #require(ContentClassifier.classify(text("#FF8800")))
        #expect(result.kind == .color)
        #expect(result.preview.color?.hex == "#FF8800")
    }

    @Test func colorHintWithoutText() throws {
        let content = CapturedContent(
            representations: [ClipRepresentation(type: PasteboardTypeID.color, data: Data([1, 2, 3]))],
            hints: ContentHints(color: ColorValue(red: 1, green: 0, blue: 0))
        )
        let result = try #require(ContentClassifier.classify(content))
        #expect(result.kind == .color)
        #expect(result.preview.title == "#FF0000")
    }

    @Test func filesWinOverText() throws {
        let content = CapturedContent(representations: [
            ClipRepresentation(item: 0, type: PasteboardTypeID.fileURL, data: Data("file:///Users/a/Rechnung.pdf".utf8)),
            ClipRepresentation(item: 0, type: PasteboardTypeID.plainText, data: Data("Rechnung.pdf".utf8)),
            ClipRepresentation(item: 1, type: PasteboardTypeID.fileURL, data: Data("file:///Users/a/Foto%201.jpg".utf8)),
        ])
        let result = try #require(ContentClassifier.classify(content))
        #expect(result.kind == .files)
        #expect(result.preview.fileNames == ["Rechnung.pdf", "Foto 1.jpg"])
        #expect(result.preview.lineCount == 2)
        #expect(result.text == nil)
    }

    @Test func textWinsOverImage() throws {
        let result = try #require(ContentClassifier.classify(text("A1\tB1", extra: [
            ClipRepresentation(type: PasteboardTypeID.png, data: Self.png(width: 10, height: 10)),
        ])))
        #expect(result.kind == .text)
    }

    @Test func imageAlone() throws {
        let content = CapturedContent(representations: [ClipRepresentation(type: PasteboardTypeID.png, data: Self.png(width: 1920, height: 1080))])
        let result = try #require(ContentClassifier.classify(content))
        #expect(result.kind == .image)
        #expect(result.preview.imageSize == PixelSize(width: 1920, height: 1080))
        #expect(result.preview.capturedFrom == nil)
        #expect(result.preview.searchText.isEmpty)
    }

    @Test func screenshotKeepsWhereItWasTaken() throws {
        let content = CapturedContent(
            representations: [ClipRepresentation(type: PasteboardTypeID.png, data: Self.png(width: 800, height: 600))],
            hints: ContentHints(capturedFrom: "Safari – JIRA-1234 Übersicht")
        )
        let result = try #require(ContentClassifier.classify(content))
        #expect(result.kind == .image)
        #expect(result.preview.capturedFrom == "Safari – JIRA-1234 Übersicht")
        #expect(result.preview.searchText == "safari – jira-1234 ubersicht")
    }

    @Test func previewsStoredBeforeDecodeWithoutCapturedFrom() throws {
        let old = Data(#"{"title":"Hallo","lineCount":1,"characterCount":5,"fileNames":[],"isFormatted":false,"searchText":"hallo"}"#.utf8)
        let preview = try JSONDecoder().decode(ClipPreview.self, from: old)
        #expect(preview.title == "Hallo")
        #expect(preview.capturedFrom == nil)
    }

    @Test func nothingUsable() {
        #expect(ContentClassifier.classify(CapturedContent(representations: [])) == nil)
        #expect(ContentClassifier.classify(text("")) == nil)
    }

    @Test func searchTextIsFolded() throws {
        let result = try #require(ContentClassifier.classify(text("Café  Über\nGRÖSSE")))
        #expect(result.preview.searchText == "cafe uber grosse")
    }

    @Test func longFirstLineIsShortened() throws {
        let result = try #require(ContentClassifier.classify(text(String(repeating: "a", count: 500))))
        #expect(result.preview.title.count == 301)
        #expect(result.preview.characterCount == 500)
    }

    /// A minimal PNG header with the given size (enough for `PNGInfo`).
    static func png(width: Int, height: Int) -> Data {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
        for value in [width, height] {
            bytes += [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        }
        return Data(bytes + [8, 6, 0, 0, 0])
    }
}

struct PNGInfoTests {
    @Test func rejectsOtherData() {
        #expect(PNGInfo.size(of: Data("not a png at all, really not".utf8)) == nil)
        #expect(PNGInfo.size(of: Data()) == nil)
    }
}
