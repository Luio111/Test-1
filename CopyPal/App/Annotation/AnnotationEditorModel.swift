import AppKit
import Observation
import CopyPalCore
import CopyPalSystem

/// One markup session (ROADMAP R33): the picture, its marks, the tool and the styles.
/// The canvas and the toolbars only ask and tell this model; it keeps ⌘Z in one place.
@MainActor
@Observable
final class AnnotationEditorModel {
    enum Finish {
        case copy
        case save
        case cancel
    }

    let image: ImageBox
    /// Pixels per point of the picture (2 for a Retina screenshot).
    let scale: CGFloat
    private(set) var document = AnnotationDocument()
    private(set) var tool: AnnotationTool = .arrow
    private(set) var selection: UUID?
    /// A mark being drawn or a new text being typed: not in the document yet.
    private(set) var draft: Annotation?
    /// The text being typed: the draft's or an existing one's id.
    private(set) var editingText: UUID?
    private(set) var styles: AnnotationStyleBook
    /// The canvas redraws on every change.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onFinish: ((Finish) -> Void)?
    /// A slider is being dragged: one ⌘Z step for the whole drag.
    @ObservationIgnored private var isAdjustingStyle = false
    /// The colour panel reports every move of its wheel: one step per mark and second.
    @ObservationIgnored private var lastCoalescedChange: (id: UUID, at: ContinuousClock.Instant)?

    init(image: ImageBox, scale: CGFloat) {
        self.image = image
        self.scale = max(scale, 1)
        styles = AppSettings.annotationStyles
    }

    /// The picture in points.
    var size: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    var hasMarkup: Bool {
        !document.isEmpty || draft.map { !AnnotationGeometry.isNegligible($0.shape) } ?? false
    }

    /// Every mark as painted now, the draft on top.
    var visibleAnnotations: [Annotation] {
        document.items + (draft.map { [$0] } ?? [])
    }

    /// The text measure of the geometry: the renderer's font.
    let measure: AnnotationGeometry.TextMeasure = AnnotationRenderer.textSize

    private func changed() {
        onChange?()
    }

    // MARK: Tools and style

    func selectTool(_ tool: AnnotationTool) {
        endTextEditing()
        self.tool = tool
        selection = nil
        changed()
    }

    /// What the style controls work on: the text being typed, else the selected mark.
    var styledAnnotation: Annotation? {
        if let editingText {
            return draft?.id == editingText ? draft : document.item(editingText)
        }
        return selection.flatMap { document.item($0) }
    }

    /// The tool whose controls show (font size for text, filling for boxes …).
    var styleTool: AnnotationTool {
        styledAnnotation?.tool ?? tool
    }

    var style: AnnotationStyle {
        styledAnnotation?.style ?? styles[tool]
    }

    /// Changes the style of the mark at hand (one ⌘Z step) and remembers it as the
    /// tool's style for the next marks and the next screenshot. `coalescing`: changes
    /// that follow each other within a second are one step (the colour panel).
    func changeStyle(coalescing: Bool = false, _ change: (inout AnnotationStyle) -> Void) {
        let target = styleTool
        var newStyle = style
        change(&newStyle)
        newStyle = newStyle.clamped(for: target)
        if target != .select {
            styles[target] = newStyle
            AppSettings.annotationStyles = styles
        }
        if var mark = styledAnnotation, mark.style != newStyle {
            mark.style = newStyle
            if draft?.id == mark.id {
                draft = mark
            } else {
                // Typing has its own step (from `editText`), a slider drag one for the drag.
                var recording = editingText == nil && !isAdjustingStyle
                if coalescing, let last = lastCoalescedChange, last.id == mark.id, ContinuousClock.now - last.at < .seconds(1) {
                    recording = false
                }
                document.replace(mark, recordingUndo: recording)
                lastCoalescedChange = coalescing ? (mark.id, ContinuousClock.now) : nil
            }
        }
        changed()
    }

    /// A slider started or ended a drag.
    func adjustingStyle(_ adjusting: Bool) {
        guard adjusting != isAdjustingStyle else { return }
        isAdjustingStyle = adjusting
        guard editingText == nil else { return }
        if adjusting {
            document.checkpoint()
        } else {
            document.discardCheckpointIfUnchanged()
            changed()
        }
    }

    /// [ and ]: the line or the text one step thinner or thicker.
    func adjustSize(by steps: Int) {
        let target = styleTool
        let step = AnnotationStyle.sizeStep(for: target) * Double(steps)
        changeStyle { style in
            if target.usesFontSize {
                style.fontSize += step
            } else {
                style.lineWidth += step
            }
        }
    }

    // MARK: Drawing

    func beginDraft(_ mark: Annotation) {
        endTextEditing()
        selection = nil
        draft = mark
        changed()
    }

    func updateDraft(_ shape: AnnotationShape) {
        guard draft != nil, editingText == nil else { return }
        draft?.shape = shape
        changed()
    }

    /// The finished mark goes into the document and stays selected, so its colour
    /// and size can still be changed. A click without a drag leaves nothing.
    func commitDraft() {
        guard let mark = draft, editingText == nil else { return }
        draft = nil
        if !AnnotationGeometry.isNegligible(mark.shape) {
            document.add(mark)
            selection = mark.id
        }
        changed()
    }

    // MARK: Text

    /// A new text at `origin` (the top-left corner of its box).
    func beginText(at origin: CGPoint) {
        endTextEditing()
        selection = nil
        let mark = Annotation(shape: .text("", at: origin), style: styles[.text])
        draft = mark
        editingText = mark.id
        changed()
    }

    /// Types into an existing text again.
    func editText(_ id: UUID) {
        endTextEditing()
        guard let mark = document.item(id), case .text = mark.shape else { return }
        document.checkpoint()
        selection = nil
        editingText = id
        changed()
    }

    var editingString: String? {
        guard let mark = styledAnnotation, mark.id == editingText, case let .text(string, _) = mark.shape else { return nil }
        return string
    }

    func updateEditingText(_ string: String) {
        guard let id = editingText else { return }
        if var mark = draft, mark.id == id, case let .text(_, origin) = mark.shape {
            mark.shape = .text(string, at: origin)
            draft = mark
        } else if var mark = document.item(id), case let .text(_, origin) = mark.shape {
            mark.shape = .text(string, at: origin)
            document.replace(mark, recordingUndo: false)
        }
        changed()
    }

    /// Esc, ⌘⏎ or a click elsewhere: the text is done. An empty text disappears.
    func endTextEditing() {
        guard let id = editingText else { return }
        editingText = nil
        if var mark = draft, mark.id == id {
            draft = nil
            if case let .text(string, origin) = mark.shape {
                mark.shape = .text(string.trimmingCharacters(in: .whitespacesAndNewlines), at: origin)
            }
            if !AnnotationGeometry.isNegligible(mark.shape) {
                document.add(mark)
                selection = id
            }
        } else if var mark = document.item(id), case let .text(string, origin) = mark.shape {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                document.remove(id, recordingUndo: false)
            } else {
                mark.shape = .text(trimmed, at: origin)
                document.replace(mark, recordingUndo: false)
                selection = id
            }
            document.discardCheckpointIfUnchanged()
        }
        changed()
    }

    // MARK: Selection

    func select(_ id: UUID?) {
        endTextEditing()
        selection = id
        changed()
    }

    /// Before a move or resize by mouse: the whole drag is one ⌘Z step.
    func beginChange() {
        document.checkpoint()
    }

    func update(_ mark: Annotation) {
        document.replace(mark, recordingUndo: false)
        changed()
    }

    func endChange() {
        document.discardCheckpointIfUnchanged()
        changed()
    }

    func deleteSelection() {
        guard let selection else { return }
        document.remove(selection)
        self.selection = nil
        changed()
    }

    /// The arrow keys: the selection by one point, with ⇧ by ten.
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let selection, var mark = document.item(selection) else { return }
        mark.shape = mark.shape.offsetBy(dx: dx, dy: dy)
        document.replace(mark)
        changed()
    }

    // MARK: Undo

    var canUndo: Bool {
        document.canUndo || editingText != nil
    }

    var canRedo: Bool {
        document.canRedo
    }

    func undo() {
        endTextEditing()
        draft = nil
        document.undo()
        dropStaleSelection()
        changed()
    }

    func redo() {
        endTextEditing()
        document.redo()
        dropStaleSelection()
        changed()
    }

    private func dropStaleSelection() {
        if let selection, document.item(selection) == nil {
            self.selection = nil
        }
    }

    // MARK: Finish

    func finish(_ action: Finish) {
        endTextEditing()
        selection = nil
        changed()
        onFinish?(action)
    }

    /// The picture with every mark, in its own pixels; off the main thread, as a long
    /// stitched screenshot has many megapixels.
    func rendered() async -> ImageBox? {
        let items = document.items
        let image = self.image
        let scale = self.scale
        return await Task.detached(priority: .userInitiated) { () -> ImageBox? in
            AnnotationRenderer.render(image.image, scale: scale, annotations: items).map { ImageBox($0) }
        }.value
    }
}
