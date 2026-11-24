import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import CopyPalCore

struct AnnotationTests {
    /// 10 pt per character and 1.2 lines per font size: enough to test the boxes.
    private let measure: AnnotationGeometry.TextMeasure = { text, fontSize in
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let widest = lines.map(\.count).max() ?? 0
        return CGSize(width: CGFloat(widest) * 10, height: CGFloat(lines.count) * CGFloat(fontSize) * 1.2)
    }

    // MARK: Tools and styles

    @Test func everyToolHasItsOwnLetter() {
        let keys = AnnotationTool.allCases.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(AnnotationTool.tool(forKey: "A") == .arrow)
        #expect(AnnotationTool.tool(forKey: "t") == .text)
        #expect(AnnotationTool.tool(forKey: "x") == nil)
    }

    @Test func textOnABubbleIsWhiteOnDarkAndBlackOnLightColours() {
        #expect(AnnotationColor.red.textColorOnTop == .white)
        #expect(AnnotationColor.blue.textColorOnTop == .white)
        #expect(AnnotationColor.purple.textColorOnTop == .white)
        #expect(AnnotationColor.black.textColorOnTop == .white)
        #expect(AnnotationColor.yellow.textColorOnTop == .black)
        #expect(AnnotationColor.green.textColorOnTop == .black)
        #expect(AnnotationColor.white.textColorOnTop == .black)
    }

    @Test func stylesStayInsideTheOfferedSizes() {
        var style = AnnotationStyle(color: .red, lineWidth: 200, fontSize: 2)
        style = style.clamped(for: .pen)
        #expect(style.lineWidth == AnnotationStyle.lineWidthRange.upperBound)
        #expect(style.fontSize == AnnotationStyle.fontSizeRange.lowerBound)
        // The highlighter is allowed a broader stroke.
        #expect(AnnotationStyle(color: .yellow, lineWidth: 40).clamped(for: .highlighter).lineWidth == 40)
        #expect(AnnotationStyle(color: .yellow, lineWidth: 40).clamped(for: .line).lineWidth == 24)
    }

    @Test func theStyleBookRemembersEveryToolAndSurvivesDamagedData() throws {
        var book = AnnotationStyleBook()
        #expect(book[.highlighter].color == .yellow)
        var text = book[.text]
        text.fontSize = 36
        text.color = .blue
        book[.text] = text
        let restored = AnnotationStyleBook.decoded(book.encoded())
        #expect(restored[.text].fontSize == 36)
        #expect(restored[.text].color == .blue)
        #expect(restored[.pen] == AnnotationStyle.defaults(for: .pen))
        #expect(AnnotationStyleBook.decoded(Data("nonsense".utf8)) == AnnotationStyleBook())
        #expect(AnnotationStyleBook.decoded(nil) == AnnotationStyleBook())
    }

    // MARK: Geometry

    @Test func rectanglesFollowTheDragInEveryDirection() {
        let start = CGPoint(x: 100, y: 100)
        #expect(AnnotationGeometry.rect(from: start, to: CGPoint(x: 40, y: 160)) == CGRect(x: 40, y: 100, width: 60, height: 60))
        // ⇧: a square, towards the pointer.
        #expect(AnnotationGeometry.rect(from: start, to: CGPoint(x: 60, y: 110), square: true) == CGRect(x: 60, y: 100, width: 40, height: 40))
        // ⌥: from the centre.
        #expect(AnnotationGeometry.rect(from: start, to: CGPoint(x: 130, y: 110), fromCenter: true) == CGRect(x: 70, y: 90, width: 60, height: 20))
    }

    @Test func shiftSnapsLinesToFortyFiveDegrees() {
        let start = CGPoint(x: 0, y: 0)
        let flat = AnnotationGeometry.snapped(CGPoint(x: 100, y: 8), from: start)
        #expect(abs(flat.y) < 0.001)
        let diagonal = AnnotationGeometry.snapped(CGPoint(x: 100, y: 90), from: start)
        #expect(abs(diagonal.x - diagonal.y) < 0.001)
        let upward = AnnotationGeometry.snapped(CGPoint(x: 3, y: -80), from: start)
        #expect(abs(upward.x) < 0.001 && upward.y < 0)
    }

    @Test func freehandStrokesLosePointsButNotTheirShape() {
        // A straight run with jitter, then a corner.
        var points: [CGPoint] = (0...50).map { CGPoint(x: CGFloat($0) * 2, y: $0.isMultiple(of: 2) ? 0 : 0.3) }
        points += (1...50).map { CGPoint(x: 100, y: CGFloat($0) * 2) }
        let simplified = AnnotationGeometry.simplified(points, tolerance: 1)
        #expect(simplified.count == 3)
        #expect(simplified.first == points.first)
        #expect(simplified.contains(CGPoint(x: 100, y: 0)))
        #expect(simplified.last == points.last)
        #expect(AnnotationGeometry.simplified([CGPoint(x: 1, y: 1)], tolerance: 1).count == 1)
    }

    @Test func arrowHeadsGrowWithTheLineAndStayOnShortArrows() {
        let head = AnnotationGeometry.arrowHead(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), lineWidth: 5)
        #expect(head.tip == CGPoint(x: 200, y: 0))
        // Symmetric about the shaft, behind the tip, the shaft ending inside the head.
        #expect(abs(head.left.y + head.right.y) < 0.001)
        #expect(head.left.x < 200 && head.left.x == head.right.x)
        #expect(head.base.x > head.left.x && head.base.x < 200)
        let thick = AnnotationGeometry.arrowHead(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), lineWidth: 12)
        #expect(thick.left.x < head.left.x)
        // A 20 pt arrow: the head takes at most 60 % of it.
        let short = AnnotationGeometry.arrowHead(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 0), lineWidth: 12)
        #expect(short.left.x >= 8 - 0.001)
    }

    @Test func textBoxesIncludeTheBubblePadding() {
        let frame = AnnotationGeometry.textFrame("Hallo", at: CGPoint(x: 10, y: 20), fontSize: 20, measure: measure)
        let padding = AnnotationGeometry.textPadding(fontSize: 20)
        #expect(frame == CGRect(x: 10, y: 20, width: 50 + padding.width * 2, height: 24 + padding.height * 2))
        // Two lines are twice as high; an empty text still has a box to click.
        let twoLines = AnnotationGeometry.textFrame("A\nBB", at: .zero, fontSize: 20, measure: measure)
        #expect(twoLines.height == 48 + padding.height * 2)
        #expect(AnnotationGeometry.textFrame("", at: .zero, fontSize: 20, measure: measure).width > 0)
    }

    @Test func hitsLandOnWhatIsPainted() {
        let outline = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle(color: .red, lineWidth: 4))
        #expect(AnnotationGeometry.hits(outline, at: CGPoint(x: 1, y: 50), tolerance: 3, measure: measure))
        #expect(!AnnotationGeometry.hits(outline, at: CGPoint(x: 50, y: 50), tolerance: 3, measure: measure))
        var filled = outline
        filled.style.filled = true
        #expect(AnnotationGeometry.hits(filled, at: CGPoint(x: 50, y: 50), tolerance: 3, measure: measure))

        let ring = Annotation(shape: .ellipse(CGRect(x: 0, y: 0, width: 200, height: 100)), style: AnnotationStyle(color: .red, lineWidth: 4))
        #expect(AnnotationGeometry.hits(ring, at: CGPoint(x: 100, y: 1), tolerance: 3, measure: measure))
        #expect(!AnnotationGeometry.hits(ring, at: CGPoint(x: 100, y: 50), tolerance: 3, measure: measure))
        // The corner of the bounding box is outside the ellipse.
        #expect(!AnnotationGeometry.hits(ring, at: CGPoint(x: 2, y: 2), tolerance: 3, measure: measure))

        let stroke = Annotation(shape: .pen([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]), style: AnnotationStyle(color: .red, lineWidth: 10))
        #expect(AnnotationGeometry.hits(stroke, at: CGPoint(x: 50, y: 6), tolerance: 2, measure: measure))
        #expect(!AnnotationGeometry.hits(stroke, at: CGPoint(x: 50, y: 50), tolerance: 2, measure: measure))

        let label = Annotation(shape: .text("Hallo", at: CGPoint(x: 10, y: 10)), style: .defaults(for: .text))
        #expect(AnnotationGeometry.hits(label, at: CGPoint(x: 30, y: 25), tolerance: 0, measure: measure))
        #expect(!AnnotationGeometry.hits(label, at: CGPoint(x: 5, y: 5), tolerance: 0, measure: measure))
    }

    @Test func clicksWithoutADragLeaveNothingBehind() {
        #expect(AnnotationGeometry.isNegligible(.arrow(from: .zero, to: CGPoint(x: 2, y: 2))))
        #expect(!AnnotationGeometry.isNegligible(.arrow(from: .zero, to: CGPoint(x: 20, y: 0))))
        #expect(AnnotationGeometry.isNegligible(.rectangle(CGRect(x: 0, y: 0, width: 1, height: 2))))
        // A thin bar is a deliberate shape.
        #expect(!AnnotationGeometry.isNegligible(.rectangle(CGRect(x: 0, y: 0, width: 2, height: 80))))
        #expect(AnnotationGeometry.isNegligible(.text("  \n", at: .zero)))
        #expect(!AnnotationGeometry.isNegligible(.pen([CGPoint(x: 1, y: 1)])))
    }

    // MARK: Moving and handles

    @Test func handlesResizeAroundTheOppositeCorner() {
        let shape = AnnotationShape.rectangle(CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(shape.handles.count == 4)
        let resized = shape.moving(.bottomRight, to: CGPoint(x: 60, y: 30))
        #expect(resized == .rectangle(CGRect(x: 10, y: 10, width: 50, height: 20)))
        // Dragged past the fixed corner: the rectangle flips instead of turning negative.
        let flipped = shape.moving(.topLeft, to: CGPoint(x: 130, y: 80))
        #expect(flipped == .rectangle(CGRect(x: 110, y: 60, width: 20, height: 20)))
        let square = AnnotationShape.ellipse(CGRect(x: 0, y: 0, width: 10, height: 10)).moving(.bottomRight, to: CGPoint(x: 50, y: 20), constrained: true)
        #expect(square == .ellipse(CGRect(x: 0, y: 0, width: 50, height: 50)))
    }

    @Test func lineEndsMoveOneAtATime() {
        let arrow = AnnotationShape.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        #expect(arrow.moving(.end, to: CGPoint(x: 50, y: 50)) == .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50)))
        #expect(arrow.moving(.start, to: CGPoint(x: 20, y: 20)) == .arrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 0)))
        guard case let .line(_, end) = AnnotationShape.line(from: .zero, to: CGPoint(x: 10, y: 0)).moving(.end, to: CGPoint(x: 100, y: 7), constrained: true) else {
            Issue.record("not a line")
            return
        }
        #expect(abs(end.y) < 0.001)
        #expect(AnnotationShape.text("A", at: .zero).handles.isEmpty)
    }

    @Test func movingKeepsTheShape() {
        let moved = AnnotationShape.pen([CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 5)]).offsetBy(dx: 10, dy: -1)
        #expect(moved == .pen([CGPoint(x: 11, y: 0), CGPoint(x: 15, y: 4)]))
        #expect(AnnotationShape.text("A", at: CGPoint(x: 3, y: 3)).offsetBy(dx: 1, dy: 1) == .text("A", at: CGPoint(x: 4, y: 4)))
    }

    // MARK: Document

    private enum Step {
        case undo
        case redo
    }

    /// `#expect` cannot call a mutating method itself.
    private func step(_ document: inout AnnotationDocument, _ step: Step) -> Bool {
        step == .undo ? document.undo() : document.redo()
    }

    @Test func undoAndRedoWalkThroughWholeChanges() {
        var document = AnnotationDocument()
        let arrow = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 50, y: 50)), style: .defaults(for: .arrow))
        document.add(arrow)
        var moved = arrow
        // A drag: one checkpoint, many moves.
        document.checkpoint()
        for step in 1...10 {
            moved.shape = arrow.shape.offsetBy(dx: CGFloat(step), dy: 0)
            document.replace(moved, recordingUndo: false)
        }
        #expect(document.item(arrow.id)?.shape == arrow.shape.offsetBy(dx: 10, dy: 0))
        #expect(step(&document, .undo) == true)
        #expect(document.item(arrow.id) == arrow)
        #expect(step(&document, .undo) == true)
        #expect(document.isEmpty)
        #expect(step(&document, .undo) == false)
        #expect(step(&document, .redo) == true)
        #expect(step(&document, .redo) == true)
        #expect(document.item(arrow.id)?.shape == arrow.shape.offsetBy(dx: 10, dy: 0))
        #expect(!document.canRedo)
    }

    @Test func aNewChangeClearsRedoAndAClickWithoutDragLeavesNoStep() {
        var document = AnnotationDocument()
        let box = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: .defaults(for: .rectangle))
        document.add(box)
        document.undo()
        #expect(document.canRedo)
        document.add(box)
        #expect(!document.canRedo)
        // A click on the box: checkpoint, no change.
        document.checkpoint()
        document.discardCheckpointIfUnchanged()
        #expect(step(&document, .undo) == true)
        #expect(document.isEmpty)
        #expect(!document.canUndo)
    }

    @Test func restylingAndRemovingAreSteps() {
        var document = AnnotationDocument()
        var text = Annotation(shape: .text("Hi", at: .zero), style: .defaults(for: .text))
        document.add(text)
        text.style.fontSize = 40
        document.replace(text)
        // Replacing with the same value is not a step.
        document.replace(text)
        document.remove(text.id)
        #expect(document.isEmpty)
        document.undo()
        #expect(document.item(text.id)?.style.fontSize == 40)
        document.undo()
        #expect(document.item(text.id)?.style.fontSize == 20)
    }

    @Test func theTopmostAnnotationWinsAHit() {
        var document = AnnotationDocument()
        let below = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle(color: .red, lineWidth: 4, filled: true))
        let above = Annotation(shape: .line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50)), style: .defaults(for: .line))
        document.add(below)
        document.add(above)
        #expect(document.hit(at: CGPoint(x: 50, y: 51), tolerance: 2, measure: measure) == above.id)
        #expect(document.hit(at: CGPoint(x: 50, y: 20), tolerance: 2, measure: measure) == below.id)
        #expect(document.hit(at: CGPoint(x: 300, y: 300), tolerance: 2, measure: measure) == nil)
    }

    @Test func undoKeepsAtMostItsLimit() {
        var document = AnnotationDocument()
        for index in 0..<(AnnotationDocument.undoLimit + 20) {
            document.add(Annotation(shape: .pen([CGPoint(x: index, y: 0)]), style: .defaults(for: .pen)))
        }
        var steps = 0
        while document.undo() {
            steps += 1
        }
        #expect(steps == AnnotationDocument.undoLimit)
        #expect(document.items.count == 20)
    }
}
