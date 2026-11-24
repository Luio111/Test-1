import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The marks on one screenshot, bottom to top, with ⌘Z and ⇧⌘Z. Undo keeps whole
/// states: a drag is one step however many moves it takes.
public struct AnnotationDocument: Sendable, Equatable {
    public private(set) var items: [Annotation]
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    public static let undoLimit = 200

    public init(items: [Annotation] = []) {
        self.items = items
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public func item(_ id: UUID) -> Annotation? {
        items.first { $0.id == id }
    }

    /// Remembers the state for ⌘Z. Called once before a change made in steps (a drag);
    /// the single changes below call it themselves.
    public mutating func checkpoint() {
        undoStack.append(items)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
        redoStack.removeAll()
    }

    /// Forgets the last checkpoint when nothing changed since (a click that did not drag).
    public mutating func discardCheckpointIfUnchanged() {
        if undoStack.last == items {
            undoStack.removeLast()
        }
    }

    public mutating func add(_ annotation: Annotation) {
        checkpoint()
        items.append(annotation)
    }

    /// Replaces the annotation with the same id. `recordingUndo: false` while a drag
    /// is under way (it called `checkpoint()` at its start).
    public mutating func replace(_ annotation: Annotation, recordingUndo: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == annotation.id }), items[index] != annotation else { return }
        if recordingUndo {
            checkpoint()
        }
        items[index] = annotation
    }

    public mutating func remove(_ id: UUID, recordingUndo: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if recordingUndo {
            checkpoint()
        }
        items.remove(at: index)
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(items)
        items = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(items)
        items = next
        return true
    }

    /// The topmost annotation under `point`.
    public func hit(at point: CGPoint, tolerance: CGFloat, measure: AnnotationGeometry.TextMeasure) -> UUID? {
        items.last { AnnotationGeometry.hits($0, at: point, tolerance: tolerance, measure: measure) }?.id
    }
}
