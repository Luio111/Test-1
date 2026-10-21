import AppKit
import CopyPalCore
import CopyPalSystem

/// The picture with its marks, drawn and edited with the mouse (ROADMAP R33). Scaled
/// to fit the window, never enlarged; a very tall stitched picture fills the width and
/// scrolls. Coordinates of the marks are points of the picture, y down, like the view.
final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    let model: AnnotationEditorModel
    private(set) var zoom: CGFloat = 1
    /// The picture's top-left corner in the view.
    private var pictureOrigin: CGPoint = .zero
    private var drag: Drag?
    private var textView: AnnotationTextView?
    private let textUndo = UndoManager()
    /// Room around the picture.
    private static let margin: CGFloat = 24

    private enum Drag {
        case drawing(start: CGPoint)
        case moving(id: UUID, start: CGPoint, original: AnnotationShape)
        case resizing(id: UUID, handle: AnnotationHandle, original: AnnotationShape)
    }

    init(model: AnnotationEditorModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: model.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Bildschirmfoto mit Markierungen"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // MARK: Layout

    /// Fits the picture into the scroll view's visible size.
    func fit(in viewport: CGSize) {
        let picture = model.size
        guard picture.width > 0, picture.height > 0 else { return }
        let margin = Self.margin
        let availableWidth = max(viewport.width - margin * 2, 40)
        let availableHeight = max(viewport.height - margin * 2, 40)
        let fitWidth = min(1, availableWidth / picture.width)
        let fitAll = min(fitWidth, availableHeight / picture.height)
        // A long page shrunk to a sliver is useless: fill the width and scroll instead.
        zoom = fitAll < fitWidth * 0.5 ? fitWidth : fitAll
        let content = CGSize(width: picture.width * zoom, height: picture.height * zoom)
        let size = CGSize(width: max(viewport.width, content.width + margin * 2), height: max(viewport.height, content.height + margin * 2))
        pictureOrigin = CGPoint(x: ((size.width - content.width) / 2).rounded(), y: ((size.height - content.height) / 2).rounded())
        if frame.size != size {
            setFrameSize(size)
        }
        syncTextView()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private var pictureRect: CGRect {
        CGRect(origin: pictureOrigin, size: CGSize(width: model.size.width * zoom, height: model.size.height * zoom))
    }

    /// A point of the view as a point of the picture.
    func picturePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - pictureOrigin.x) / zoom, y: (point.y - pictureOrigin.y) / zoom)
    }

    /// A point of the picture in the view.
    func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: pictureOrigin.x + point.x * zoom, y: pictureOrigin.y + point.y * zoom)
    }

    /// Called by the model after every change.
    func modelDidChange() {
        syncTextView()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = pictureRect
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 14, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.restoreGState()

        // The view is flipped, a CGImage is drawn y up: flip around the picture.
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(model.image.image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()

        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: zoom, y: zoom)
        AnnotationRenderer.draw(model.visibleAnnotations, in: context)
        context.restoreGState()

        drawSelection(in: context)
    }

    /// A dashed frame around the selected mark (or the text being typed) and its handles.
    private func drawSelection(in context: CGContext) {
        guard let mark = model.styledAnnotation, drag == nil || isResizingOrMoving else { return }
        let bounds = AnnotationGeometry.bounds(of: mark, measure: model.measure)
        let frame = CGRect(origin: viewPoint(bounds.origin), size: CGSize(width: bounds.width * zoom, height: bounds.height * zoom)).insetBy(dx: -4, dy: -4)
        let accent = NSColor.controlAccentColor.cgColor
        context.saveGState()
        context.setStrokeColor(accent)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
        guard mark.id != model.editingText else { return }
        for (_, point) in mark.shape.handles {
            let center = viewPoint(point)
            let knob = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: knob)
            context.setStrokeColor(accent)
            context.setLineWidth(2)
            context.strokeEllipse(in: knob.insetBy(dx: 1, dy: 1))
        }
    }

    private var isResizingOrMoving: Bool {
        switch drag {
        case .moving, .resizing: true
        case .drawing, nil: false
        }
    }

    // MARK: Cursor

    override func resetCursorRects() {
        let cursor: NSCursor
        switch model.tool {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        let area = pictureRect.intersection(visibleRect)
        if !area.isNull {
            addCursorRect(area, cursor: cursor)
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = picturePoint(convert(event.locationInWindow, from: nil))
        // A click elsewhere ends the typing; the next click draws.
        if model.editingText != nil {
            model.endTextEditing()
            _ = window?.makeFirstResponder(self)
            return
        }
        _ = window?.makeFirstResponder(self)
        let tolerance = 5 / zoom
        // The selection's handles resize it, whatever the tool.
        if let id = model.selection, let mark = model.document.item(id),
           let handle = mark.shape.handles.first(where: { AnnotationGeometry.distance($0.point, point) <= 8 / zoom })?.handle {
            model.beginChange()
            drag = .resizing(id: id, handle: handle, original: mark.shape)
            return
        }
        let hit = model.document.hit(at: point, tolerance: tolerance, measure: model.measure)
        switch model.tool {
        case .select:
            guard let hit, let mark = model.document.item(hit) else {
                model.select(nil)
                return
            }
            if event.clickCount == 2, case .text = mark.shape {
                model.editText(hit)
                return
            }
            model.select(hit)
            model.beginChange()
            drag = .moving(id: hit, start: point, original: mark.shape)
        case .text:
            if let hit, let mark = model.document.item(hit), case .text = mark.shape {
                model.editText(hit)
                return
            }
            // The click sets where the first line sits, halfway up.
            let style = model.styles[.text]
            let box = AnnotationGeometry.textFrame("", at: .zero, fontSize: style.fontSize, measure: model.measure)
            let padding = AnnotationGeometry.textPadding(fontSize: style.fontSize)
            model.beginText(at: CGPoint(x: point.x - padding.width, y: point.y - box.height / 2))
        default:
            let start = clamped(point)
            let shape: AnnotationShape
            switch model.tool {
            case .pen: shape = .pen([start])
            case .highlighter: shape = .highlighter([start])
            case .line: shape = .line(from: start, to: start)
            case .arrow: shape = .arrow(from: start, to: start)
            case .rectangle: shape = .rectangle(CGRect(origin: start, size: .zero))
            case .ellipse: shape = .ellipse(CGRect(origin: start, size: .zero))
            case .select, .text: return
            }
            model.beginDraft(Annotation(shape: shape, style: model.styles[model.tool]))
            drag = .drawing(start: start)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(picturePoint(convert(event.locationInWindow, from: nil)))
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        switch drag {
        case let .drawing(start):
            guard let draft = model.draft else { return }
            switch draft.shape {
            case let .pen(points):
                model.updateDraft(.pen(shift ? [start, AnnotationGeometry.snapped(point, from: start)] : points + [point]))
            case let .highlighter(points):
                model.updateDraft(.highlighter(shift ? [start, AnnotationGeometry.snapped(point, from: start)] : points + [point]))
            case .line:
                model.updateDraft(.line(from: start, to: shift ? AnnotationGeometry.snapped(point, from: start) : point))
            case .arrow:
                model.updateDraft(.arrow(from: start, to: shift ? AnnotationGeometry.snapped(point, from: start) : point))
            case .rectangle:
                model.updateDraft(.rectangle(AnnotationGeometry.rect(from: start, to: point, square: shift, fromCenter: option)))
            case .ellipse:
                model.updateDraft(.ellipse(AnnotationGeometry.rect(from: start, to: point, square: shift, fromCenter: option)))
            case .text:
                break
            }
        case let .moving(id, start, original):
            guard var mark = model.document.item(id) else { return }
            mark.shape = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            model.update(mark)
        case let .resizing(id, handle, original):
            guard var mark = model.document.item(id) else { return }
            mark.shape = original.moving(handle, to: point, constrained: shift)
            model.update(mark)
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .drawing:
            // The mouse reports a point every few pixels; the stroke needs far fewer.
            if let draft = model.draft {
                switch draft.shape {
                case let .pen(points):
                    model.updateDraft(.pen(AnnotationGeometry.simplified(points, tolerance: 0.35 / zoom)))
                case let .highlighter(points):
                    model.updateDraft(.highlighter(AnnotationGeometry.simplified(points, tolerance: 0.35 / zoom)))
                default:
                    break
                }
            }
            drag = nil
            model.commitDraft()
        case .moving, .resizing:
            drag = nil
            model.endChange()
        case nil:
            break
        }
    }

    /// Inside the picture, so no mark ends up where nobody sees it.
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), model.size.width), y: min(max(point.y, 0), model.size.height))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.isDisjoint(with: [.command, .control, .option]), let character = event.charactersIgnoringModifiers?.first {
            if let tool = AnnotationTool.tool(forKey: character) {
                model.selectTool(tool)
                return
            }
            switch character {
            case "[":
                model.adjustSize(by: -1)
                return
            case "]":
                model.adjustSize(by: 1)
                return
            default:
                break
            }
        }
        let step: CGFloat = flags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117:
            model.deleteSelection()
        case 36, 76:
            model.finish(.copy)
        case 53:
            if model.selection != nil {
                model.select(nil)
            } else {
                model.finish(.cancel)
            }
        case 123 where model.selection != nil:
            model.nudgeSelection(dx: -step, dy: 0)
        case 124 where model.selection != nil:
            model.nudgeSelection(dx: step, dy: 0)
        case 125 where model.selection != nil:
            model.nudgeSelection(dx: 0, dy: step)
        case 126 where model.selection != nil:
            model.nudgeSelection(dx: 0, dy: -step)
        default:
            super.keyDown(with: event)
        }
    }

    /// ⌘C (the Edit menu): the picture with its marks.
    @objc func copy(_ sender: Any?) {
        model.finish(.copy)
    }

    // MARK: Typing

    /// Puts a text view over the text being typed, or takes it away. It only takes the
    /// keys and shows the caret; the text itself is painted like every mark, so it looks
    /// while typing as it will in the picture.
    private func syncTextView() {
        guard let id = model.editingText, let mark = model.styledAnnotation, mark.id == id,
              case let .text(string, origin) = mark.shape else {
            if let textView {
                self.textView = nil
                textView.delegate = nil
                let wasFocused = window?.firstResponder === textView
                textView.removeFromSuperview()
                textUndo.removeAllActions()
                if wasFocused {
                    _ = window?.makeFirstResponder(self)
                }
            }
            return
        }
        let view = textView ?? makeTextView(string)
        let style = mark.style
        let font = AnnotationRenderer.font(size: style.fontSize * zoom) as NSFont
        if view.font != font {
            view.font = font
            view.typingAttributes[.font] = font
        }
        let caret = style.textBackground ? style.color.textColorOnTop : style.color
        view.insertionPointColor = NSColor(cgColor: AnnotationRenderer.cgColor(caret)) ?? .labelColor
        if view.string != string {
            view.string = string
        }
        let padding = AnnotationGeometry.textPadding(fontSize: style.fontSize)
        let size = model.measure(string, style.fontSize)
        let topLeft = viewPoint(CGPoint(x: origin.x + padding.width, y: origin.y + padding.height))
        view.frame = CGRect(x: topLeft.x, y: topLeft.y, width: size.width * zoom + 12, height: size.height * zoom)
        if window?.firstResponder !== view {
            _ = window?.makeFirstResponder(view)
        }
    }

    private func makeTextView(_ string: String) -> AnnotationTextView {
        let view = AnnotationTextView(frame: .zero)
        view.string = string
        view.delegate = self
        addSubview(view)
        textView = view
        return view
    }

    func textDidChange(_ notification: Notification) {
        guard let textView else { return }
        model.updateEditingText(textView.string)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Esc ends the typing (after the text view is done with the key: ending removes
        // it); ⏎ starts a new line.
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            Task { @MainActor [weak self] in
                self?.model.endTextEditing()
            }
            return true
        }
        return false
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        textUndo
    }

    #if DEBUG
    /// Self-test: where a point of the picture is on screen.
    func screenPointForSelfTest(_ point: CGPoint) -> CGPoint? {
        guard let window else { return nil }
        let inWindow = convert(viewPoint(point), to: nil)
        return window.convertPoint(toScreen: inWindow)
    }

    var isTypingForSelfTest: Bool {
        textView != nil && window?.firstResponder === textView
    }
    #endif
}

/// Takes the keys of a text being typed; the canvas paints the letters.
final class AnnotationTextView: NSTextView {
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        textColor = .clear
        typingAttributes[.foregroundColor] = NSColor.clear
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isHorizontallyResizable = true
        isVerticallyResizable = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        focusRingType = .none
        setAccessibilityLabel(String(localized: "Text der Markierung"))
    }
}
