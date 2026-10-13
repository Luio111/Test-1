import Testing
@testable import CopyPalCore

/// A tall synthetic page: one unique color per text row, white gaps every few rows,
/// optionally a fixed header and footer painted over every frame of the viewport.
private struct SyntheticPage {
    let width = 120
    let viewport: Int
    let header: Int
    let footer: Int
    /// Content repeats with this period (nil: every row unique).
    var period: Int? = nil

    init(viewport: Int = 400, header: Int = 0, footer: Int = 0, period: Int? = nil) {
        self.viewport = viewport
        self.header = header
        self.footer = footer
        self.period = period
    }

    private func paint(_ buffer: inout PixelBuffer, row: Int, b: UInt8, g: UInt8, r: UInt8) {
        buffer.fill(PixelRect(x: 0, y: row, width: width, height: 1), b: b, g: g, r: r)
    }

    private func paintContent(_ buffer: inout PixelBuffer, row: Int, documentRow: Int) {
        let index = period.map { documentRow % $0 } ?? documentRow
        if index % 10 >= 7 {
            paint(&buffer, row: row, b: 255, g: 255, r: 255)
        } else {
            paint(&buffer, row: row, b: UInt8(index & 0xFF), g: UInt8((index >> 8) & 0xFF), r: UInt8((index * 7919) & 0xFF))
        }
    }

    /// The viewport scrolled to `offset` (document row at the top).
    func frame(offset: Int) -> PixelBuffer {
        var buffer = PixelBuffer(width: width, height: viewport)
        for row in 0..<viewport {
            if row < header {
                paint(&buffer, row: row, b: 200, g: 200, r: UInt8(200 - row))
            } else if row >= viewport - footer {
                paint(&buffer, row: row, b: 100, g: UInt8(50 + row - (viewport - footer)), r: 50)
            } else {
                paintContent(&buffer, row: row, documentRow: offset + row)
            }
        }
        return buffer
    }

    /// Document rows `range` as one image, with the header above and the footer below.
    func expected(_ range: Range<Int>) -> PixelBuffer {
        var buffer = PixelBuffer(width: width, height: header + range.count + footer)
        for row in 0..<header {
            paint(&buffer, row: row, b: 200, g: 200, r: UInt8(200 - row))
        }
        for (index, documentRow) in range.enumerated() {
            paintContent(&buffer, row: header + index, documentRow: documentRow)
        }
        for row in 0..<footer {
            paint(&buffer, row: header + range.count + row, b: 100, g: UInt8(50 + row), r: 50)
        }
        return buffer
    }
}

struct VerticalStitcherTests {
    private typealias Outcome = VerticalStitcher.Outcome

    @Test func scrollingDownAppendsTheNewRows() {
        let page = SyntheticPage()
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 0))
        let first = stitcher.append(page.frame(offset: 250), direction: .down)
        let second = stitcher.append(page.frame(offset: 500), direction: .down)
        let third = stitcher.append(page.frame(offset: 730), direction: .down)
        #expect(first == .appended(rows: 250))
        #expect(second == .appended(rows: 250))
        #expect(third == .appended(rows: 230))
        #expect(stitcher.height == 1130)
        #expect(stitcher.sectionCount == 3)
        #expect(stitcher.composite() == page.expected(0..<1130))
        #expect(stitcher.lastMatchWasExact)
    }

    @Test func fixedHeaderAndFooterAppearOnce() {
        let page = SyntheticPage(viewport: 400, header: 20, footer: 12)
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 0))
        let first = stitcher.append(page.frame(offset: 200), direction: .down)
        #expect(first == .appended(rows: 200))
        #expect(stitcher.header == 20)
        #expect(stitcher.footer == 12)
        let second = stitcher.append(page.frame(offset: 400), direction: .down)
        #expect(second == .appended(rows: 200))
        // Content rows 20 … 788 (the first frame shows rows 20–387 under its header).
        #expect(stitcher.composite() == page.expected(20..<788))
    }

    @Test func scrollingUpPrependsAboveTheFirstFrame() {
        let page = SyntheticPage(viewport: 400, header: 16)
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 1000))
        let first = stitcher.append(page.frame(offset: 800), direction: .up)
        let second = stitcher.append(page.frame(offset: 650), direction: .up)
        #expect(first == .appended(rows: 200))
        #expect(second == .appended(rows: 150))
        #expect(stitcher.composite() == page.expected(666..<1400))
    }

    @Test func sameFrameIsUnchangedAndWrongDirectionIsRefused() {
        let page = SyntheticPage()
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 0))
        let still = stitcher.append(page.frame(offset: 0), direction: .down)
        let moved = stitcher.append(page.frame(offset: 250), direction: .down)
        let stillAgain = stitcher.append(page.frame(offset: 250), direction: .down)
        let back = stitcher.append(page.frame(offset: 100), direction: .up)
        #expect(still == .unchanged)
        #expect(moved == .appended(rows: 250))
        #expect(stillAgain == .unchanged)
        #expect(back == .wrongDirection)
        #expect(stitcher.height == 650)
    }

    @Test func repeatedContentIsAmbiguousNotGuessed() {
        let page = SyntheticPage(period: 220)
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 0))
        let outcome = stitcher.append(page.frame(offset: 250), direction: .down)
        #expect(outcome == .ambiguous)
        #expect(stitcher.height == 400)
    }

    @Test func scrollingTooFarHasNoOverlap() {
        let page = SyntheticPage()
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 0))
        let outcome = stitcher.append(page.frame(offset: 900), direction: .down)
        #expect(outcome == .noOverlap)
    }

    @Test func undoDropsTheLastSectionAndRematches() {
        let page = SyntheticPage()
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 0))
        _ = stitcher.append(page.frame(offset: 250), direction: .down)
        _ = stitcher.append(page.frame(offset: 500), direction: .down)
        let undone = stitcher.undo()
        #expect(undone)
        #expect(stitcher.height == 650)
        #expect(stitcher.sectionCount == 1)
        // The next frame is matched against the frame before the dropped section.
        let rematched = stitcher.append(page.frame(offset: 450), direction: .down)
        #expect(rematched == .appended(rows: 200))
        #expect(stitcher.composite() == page.expected(0..<850))
        let undoneOnce = stitcher.undo()
        let undoneTwice = stitcher.undo()
        let nothingLeft = stitcher.undo()
        #expect(undoneOnce && undoneTwice && !nothingLeft)
        #expect(stitcher.composite() == page.frame(offset: 0))
        // After undoing everything the direction is free again.
        let upwards = stitcher.append(page.frame(offset: -100), direction: .up)
        #expect(upwards == .appended(rows: 100))
    }

    @Test func heightLimitStopsTheCapture() {
        let page = SyntheticPage()
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 0), settings: StitchSettings(maximumHeight: 800))
        let first = stitcher.append(page.frame(offset: 250), direction: .down)
        let second = stitcher.append(page.frame(offset: 500), direction: .down)
        let third = stitcher.append(page.frame(offset: 750), direction: .down)
        #expect(first == .appended(rows: 250))
        #expect(second == .appended(rows: 250))
        #expect(third == .reachedLimit)
        #expect(stitcher.height == 900)
    }

    @Test func subPixelShiftsMatchByBands() {
        // The same content, every blue value off by one: hashes differ, bands agree.
        let page = SyntheticPage()
        var stitcher = VerticalStitcher(firstFrame: page.frame(offset: 0))
        var frame = page.frame(offset: 250)
        var index = 0
        while index < frame.bgra.count {
            frame.bgra[index] = frame.bgra[index] == 255 ? 254 : frame.bgra[index] &+ 1
            index += PixelBuffer.bytesPerPixel
        }
        let outcome = stitcher.append(frame, direction: .down)
        #expect(outcome == .appended(rows: 250))
        #expect(!stitcher.lastMatchWasExact)
    }

    @Test func rowSignaturesIgnoreTheEdges() {
        let inset = RowSignatures.sideInset(width: 400, scale: 2)
        #expect(inset == 16)
        #expect(RowSignatures.sideInset(width: 40, scale: 2) == 0)
        var a = PixelBuffer(width: 400, height: 1)
        var b = PixelBuffer(width: 400, height: 1)
        a.fill(PixelRect(x: 0, y: 0, width: 400, height: 1), b: 10, g: 20, r: 30)
        b.fill(PixelRect(x: 0, y: 0, width: 400, height: 1), b: 10, g: 20, r: 30)
        b.fill(PixelRect(x: 390, y: 0, width: 10, height: 1), b: 0, g: 0, r: 0) // a scrollbar
        #expect(RowSignatures.signature(of: a, row: 0, inset: inset) == RowSignatures.signature(of: b, row: 0, inset: inset))
        #expect(RowSignatures.signature(of: a, row: 0, inset: 0) != RowSignatures.signature(of: b, row: 0, inset: 0))
    }
}
