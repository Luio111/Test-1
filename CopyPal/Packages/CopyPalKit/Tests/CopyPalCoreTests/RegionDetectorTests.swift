import Testing
@testable import CopyPalCore

/// A 400 × 300 px screen drawn in code: a grey card with a dark border, a dark button
/// with a light label on it and three lines of "text", all on white.
private enum CardFixture {
    static let width = 400
    static let height = 300
    static let cell = 2

    static let cardBorder = PixelRect(x: 38, y: 38, width: 244, height: 204)
    static let card = PixelRect(x: 40, y: 40, width: 240, height: 200)
    static let button = PixelRect(x: 60, y: 60, width: 80, height: 24)
    static let label = PixelRect(x: 80, y: 70, width: 40, height: 4)
    static let lines = [
        PixelRect(x: 60, y: 120, width: 160, height: 4),
        PixelRect(x: 60, y: 134, width: 160, height: 4),
        PixelRect(x: 60, y: 148, width: 160, height: 4),
    ]

    static func buffer() -> PixelBuffer {
        var buffer = PixelBuffer(width: width, height: height)
        buffer.fill(PixelRect(x: 0, y: 0, width: width, height: height), b: 255, g: 255, r: 255)
        buffer.fill(cardBorder, b: 60, g: 60, r: 60)
        buffer.fill(card, b: 200, g: 200, r: 200)
        buffer.fill(button, b: 50, g: 50, r: 50)
        buffer.fill(label, b: 180, g: 180, r: 180)
        for line in lines {
            buffer.fill(line, b: 40, g: 40, r: 40)
        }
        return buffer
    }

    static func map() -> RegionMap {
        RegionDetector.analyze(LumaPlane(buffer: buffer(), cell: cell))
    }

    /// Pixels → cells.
    static func cells(_ rect: PixelRect) -> PixelRect {
        PixelRect(x: rect.x / cell, y: rect.y / cell, width: rect.width / cell, height: rect.height / cell)
    }
}

private func close(_ a: PixelRect?, _ b: PixelRect, tolerance: Int = 1) -> Bool {
    guard let a else { return false }
    return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
        && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
}

struct RegionDetectorTests {
    @Test func theCardIsAPanelIncludingItsBorder() {
        let map = CardFixture.map()
        let rungs = map.rungs(atCell: 30, 50) // card background between button and text
        #expect(rungs.element == nil)
        #expect(rungs.block == nil)
        #expect(close(rungs.panel, CardFixture.cells(CardFixture.cardBorder)))
    }

    @Test func theButtonIsAnElementOnTheCard() {
        let map = CardFixture.map()
        let rungs = map.rungs(atCell: 33, 36) // the button's dark face, left of the label
        #expect(close(rungs.element, CardFixture.cells(CardFixture.button)))
        #expect(rungs.block == nil)
        #expect(close(rungs.panel, CardFixture.cells(CardFixture.cardBorder)))
        // The label is an element of its own, nested in the button; no text block either.
        let onLabel = map.rungs(atCell: 50, 36)
        #expect(close(onLabel.element, CardFixture.cells(CardFixture.label)))
        #expect(onLabel.block == nil)
        #expect(close(onLabel.panel, CardFixture.cells(CardFixture.cardBorder)))
        // The card's border is no element: the panel covers it.
        let onBorder = map.rungs(atCell: 19, 60)
        #expect(onBorder.element == nil)
        #expect(close(onBorder.panel, CardFixture.cells(CardFixture.cardBorder)))
    }

    @Test func textLinesFormABlock() {
        let map = CardFixture.map()
        let rungs = map.rungs(atCell: 70, 61) // the first line
        #expect(close(rungs.element, CardFixture.cells(CardFixture.lines[0])))
        let allLines = PixelRect(x: 60, y: 120, width: 160, height: 32)
        #expect(close(rungs.block, CardFixture.cells(allLines)))
        #expect(close(rungs.panel, CardFixture.cells(CardFixture.cardBorder)))
        // The gap between two lines belongs to no element but is still on the card.
        let gap = map.rungs(atCell: 70, 64)
        #expect(gap.element == nil)
        #expect(close(gap.panel, CardFixture.cells(CardFixture.cardBorder)))
    }

    @Test func theRingShapedBackgroundIsNoPanel() {
        let map = CardFixture.map()
        let rungs = map.rungs(atCell: 180, 10)
        #expect(rungs.element == nil)
        #expect(rungs.panel == nil)
    }

    @Test func rungsAreClippedToTheWindow() {
        let map = CardFixture.map()
        let window = PixelRect(x: 0, y: 0, width: 100, height: 150)
        let rungs = map.rungs(atCell: 33, 36, within: window)
        #expect(rungs.panel?.maxX == 100)
        #expect(rungs.element?.maxX == 70 || rungs.element?.maxX == 71)
        let outside = map.rungs(atCell: 33, 36, within: PixelRect(x: 150, y: 0, width: 50, height: 150))
        #expect(outside.element == nil && outside.panel == nil)
    }

    @Test func anElementAsLargeAsTheScreenIsDropped() {
        var buffer = PixelBuffer(width: 400, height: 300)
        buffer.fill(PixelRect(x: 0, y: 0, width: 400, height: 300), b: 255, g: 255, r: 255)
        // A thin frame around almost the whole screen.
        buffer.fill(PixelRect(x: 4, y: 4, width: 392, height: 292), b: 0, g: 0, r: 0)
        buffer.fill(PixelRect(x: 6, y: 6, width: 388, height: 288), b: 255, g: 255, r: 255)
        let map = RegionDetector.analyze(LumaPlane(buffer: buffer, cell: 2))
        #expect(map.elementBoxes.isEmpty)
        // The white inside is a flat region of its own.
        #expect(map.rungs(atCell: 100, 75).panel != nil)
    }

    @Test func analysisIsDeterministic() {
        let a = CardFixture.map()
        let b = CardFixture.map()
        #expect(a.elementBoxes == b.elementBoxes)
        #expect(a.panelBoxes == b.panelBoxes)
        #expect(a.blockBoxes == b.blockBoxes)
        #expect(a.elementLabel == b.elementLabel)
    }

    @Test func gradientAndDilationBasics() {
        var buffer = PixelBuffer(width: 8, height: 4)
        buffer.fill(PixelRect(x: 4, y: 0, width: 4, height: 4), b: 255, g: 255, r: 255)
        let plane = LumaPlane(buffer: buffer, cell: 1)
        let gradient = plane.gradient()
        #expect(gradient[3] == 255 && gradient[4] == 255)
        #expect(gradient[0] == 0 && gradient[7] == 0)

        var mask = BitMask(width: 5, height: 5)
        mask[2, 2] = true
        let dilated = mask.dilated(radius: 1)
        #expect(dilated.bits.filter { $0 }.count == 9)
        #expect(dilated[1, 1] && dilated[3, 3] && !dilated[0, 0])
        let components = dilated.components(minCells: 1)
        #expect(components.boxes == [PixelRect(x: 1, y: 1, width: 3, height: 3)])
        #expect(components.areas == [9])
        #expect(components.labels[2 * 5 + 2] == 1 && components.labels[0] == 0)
    }

    @Test func smallComponentsAreIgnored() {
        var mask = BitMask(width: 10, height: 10)
        mask[1, 1] = true
        for x in 4..<9 { for y in 4..<9 { mask[x, y] = true } }
        let components = mask.components(minCells: 4)
        #expect(components.boxes == [PixelRect(x: 4, y: 4, width: 5, height: 5)])
        #expect(components.labels[1 * 10 + 1] == 0)
        #expect(components.labels[5 * 10 + 5] == 1)
    }

    @Test func pixelRectGeometry() {
        let a = PixelRect(x: 0, y: 0, width: 10, height: 10)
        let b = PixelRect(x: 5, y: 5, width: 10, height: 10)
        #expect(a.intersection(b) == PixelRect(x: 5, y: 5, width: 5, height: 5))
        #expect(a.union(b) == PixelRect(x: 0, y: 0, width: 15, height: 15))
        #expect(a.intersection(PixelRect(x: 10, y: 0, width: 5, height: 5)) == nil)
        #expect(a.contains(9, 9) && !a.contains(10, 9) && !a.contains(-1, 0))
        #expect(a.area == 100)
    }
}
