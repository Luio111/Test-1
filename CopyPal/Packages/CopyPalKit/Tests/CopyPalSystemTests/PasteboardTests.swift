#if os(macOS)
import AppKit
import CopyPalCore
import Testing
@testable import CopyPalSystem

/// Reading and writing on private pasteboards (never touches the user's clipboard).
@Suite(.serialized)
struct PasteboardTests {
    let budget = PasteboardReader.Budget(maxTextBytes: 2_000_000, maxImageBytes: 25_000_000)

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard.withUniqueName()
    }

    @Test func roundTripTextAndRTF() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let rtf = Data("{\\rtf1\\ansi {\\b Fett}}".utf8)
        let changeCount = PasteboardWriter.write([
            ClipRepresentation(type: PasteboardTypeID.plainText, data: Data("Fett".utf8)),
            ClipRepresentation(type: PasteboardTypeID.rtf, data: rtf),
        ], to: pasteboard)

        let types = PasteboardReader.types(of: pasteboard)
        #expect(types.contains(PasteboardTypeID.plainText))
        #expect(types.contains(PasteboardTypeID.rtf))
        // The source marker carries the bundle ID; the test runner has none.
        #expect(types.contains(PasteboardTypeID.source) == (Bundle.main.bundleIdentifier != nil))

        guard case let .content(content, _) = PasteboardReader.readNow(pasteboard, expectedChangeCount: changeCount, budget: budget) else {
            Issue.record("nothing read")
            return
        }
        #expect(content.plainText == "Fett")
        #expect(content.data(for: PasteboardTypeID.rtf) == rtf)
    }

    @Test func plainTextOnly() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardWriter.write([
            ClipRepresentation(type: PasteboardTypeID.plainText, data: Data("Fett".utf8)),
            ClipRepresentation(type: PasteboardTypeID.rtf, data: Data("{\\rtf1 Fett}".utf8)),
        ], to: pasteboard, options: PasteboardWriter.Options(plainTextOnly: true))
        let types = PasteboardReader.types(of: pasteboard)
        #expect(types.contains(PasteboardTypeID.plainText))
        #expect(!types.contains(PasteboardTypeID.rtf))
    }

    @Test func concealedMarker() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardWriter.write(
            [ClipRepresentation(type: PasteboardTypeID.plainText, data: Data("geheim".utf8))],
            to: pasteboard,
            options: PasteboardWriter.Options(localOnly: true, concealed: true)
        )
        let types = PasteboardReader.types(of: pasteboard)
        #expect(PasteboardMarkers.decide(types: types) == .skip(.concealed))
    }

    @Test func severalFiles() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b c.pdf")]
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])

        guard case let .content(content, _) = PasteboardReader.readNow(pasteboard, expectedChangeCount: pasteboard.changeCount, budget: budget) else {
            Issue.record("nothing read")
            return
        }
        #expect(content.fileURLs.map(\.lastPathComponent) == ["a.txt", "b c.pdf"])
        let classification = try #require(ContentClassifier.classify(content))
        #expect(classification.kind == .files)

        // Written back as two items again.
        let copy = makePasteboard()
        defer { copy.releaseGlobally() }
        PasteboardWriter.write(content.representations, to: copy)
        let readBack = copy.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(readBack?.map(\.lastPathComponent) == ["a.txt", "b c.pdf"])
    }

    @Test func tiffBecomesPNG() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.orange.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        pasteboard.clearContents()
        pasteboard.setData(tiff, forType: .tiff)

        guard case let .content(content, _) = PasteboardReader.readNow(pasteboard, expectedChangeCount: pasteboard.changeCount, budget: budget) else {
            Issue.record("nothing read")
            return
        }
        let png = try #require(content.data(for: PasteboardTypeID.png))
        #expect(PNGInfo.size(of: png) != nil)
        #expect(try #require(ContentClassifier.classify(content)).kind == .image)

        let thumbnail = try #require(ImageConversion.thumbnail(fromImageData: png, maxPixelSize: 10))
        let size = try #require(PNGInfo.size(of: thumbnail))
        #expect(max(size.width, size.height) <= 10)
    }

    @Test func colorObject() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([NSColor(srgbRed: 1, green: 136.0 / 255, blue: 0, alpha: 1)])

        guard case let .content(content, _) = PasteboardReader.readNow(pasteboard, expectedChangeCount: pasteboard.changeCount, budget: budget) else {
            Issue.record("nothing read")
            return
        }
        #expect(content.hints.color?.hex == "#FF8800")
    }

    @Test func tooLargeText() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(String(repeating: "x", count: 2_000), forType: .string)
        let small = PasteboardReader.Budget(maxTextBytes: 1_000, maxImageBytes: 1_000)
        #expect(PasteboardReader.readNow(pasteboard, expectedChangeCount: pasteboard.changeCount, budget: small) == .skipped(.tooLarge))
    }

    @Test func changedMeanwhile() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("a", forType: .string)
        let old = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("b", forType: .string)
        #expect(PasteboardReader.readNow(pasteboard, expectedChangeCount: old, budget: budget) == .skipped(.changedWhileReading))
    }

    @Test func asyncRead() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("im Hintergrund", forType: .string)
        let result = await PasteboardReader.read(
            pasteboardName: pasteboard.name.rawValue,
            expectedChangeCount: pasteboard.changeCount,
            budget: budget
        )
        guard case let .content(content, _) = result else {
            Issue.record("nothing read: \(result)")
            return
        }
        #expect(content.plainText == "im Hintergrund")
    }

    @MainActor
    @Test func monitorReportsChangesAndOwnWrites() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let monitor = PasteboardMonitor(pasteboard: pasteboard)
        var changes: [PasteboardMonitor.Change] = []
        monitor.onChange = { changes.append($0) }
        monitor.start()
        defer { monitor.stop() }

        pasteboard.clearContents()
        pasteboard.setString("fremd", forType: .string)
        monitor.poll()
        let own = PasteboardWriter.write([ClipRepresentation(type: PasteboardTypeID.plainText, data: Data("eigen".utf8))], to: pasteboard)
        monitor.registerOwnWrite(changeCount: own)
        monitor.poll()
        monitor.poll()

        #expect(changes.map(\.isOwnWrite) == [false, true])
        #expect(changes.first?.types.contains(PasteboardTypeID.plainText) == true)
    }
}
#endif
