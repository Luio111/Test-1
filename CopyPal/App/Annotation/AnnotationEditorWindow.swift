import AppKit
import SwiftUI
import CopyPalSystem

/// The markup window (ROADMAP R33): opens with E or "Markieren" after a screenshot
/// selection. "Kopieren" and "Sichern" hand the picture with its marks back to the
/// screenshot controller, which publishes it like ⏎ or ⌘S; the window closes first,
/// so the focus is back in the app the screenshot is meant for.
@MainActor
final class AnnotationEditorController: NSObject, NSWindowDelegate {
    let model: AnnotationEditorModel
    let canvas: AnnotationCanvasView
    var onClose: (() -> Void)?
    private(set) var window: AnnotationEditorWindow?
    private let onDone: (AnnotationEditorModel.Finish, ImageBox?) -> Void
    private var isFinishing = false

    init(image: ImageBox, scale: CGFloat, onDone: @escaping (AnnotationEditorModel.Finish, ImageBox?) -> Void) {
        model = AnnotationEditorModel(image: image, scale: scale)
        canvas = AnnotationCanvasView(model: model)
        self.onDone = onDone
        super.init()
        model.onChange = { [weak canvas] in
            canvas?.modelDidChange()
        }
        model.onFinish = { [weak self] action in
            self?.finish(action)
        }
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        FocusReturn.remember()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(canvas)
    }

    private func makeWindow() -> AnnotationEditorWindow {
        let hosting = NSHostingController(rootView: AnnotationEditorView(model: model, canvas: canvas))
        // The window keeps the size given here; SwiftUI does not resize it.
        hosting.sizingOptions = []
        let window = AnnotationEditorWindow(contentViewController: hosting)
        window.title = String(localized: "Markieren")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.backgroundColor = Theme.Colors.windowBackground
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: 760, height: 420)
        window.setContentSize(initialContentSize())
        window.center()
        window.delegate = self
        window.keyEquivalentHandler = { [weak self] event in
            self?.handleKeyEquivalent(event) ?? false
        }
        return window
    }

    /// The picture at its size plus the bars, within 90 % of the screen.
    private func initialContentSize() -> CGSize {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let picture = model.size
        // Margins around the picture, two tool rows on top, the buttons at the bottom.
        let width = min(max(picture.width + 48, 760), visible.width * 0.9)
        let height = min(max(picture.height + 48 + 150, 420), visible.height * 0.9)
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// ⌘Z, ⇧⌘Z, ⌘S, ⌘⏎ and ⌘C, before the menu sees them. While a text is typed, ⌘Z
    /// and ⌘C belong to the typing.
    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), flags.isDisjoint(with: [.control, .option]) else { return false }
        let typing = model.editingText != nil
        let typingUndo = (window?.firstResponder as? NSTextView)?.undoManager
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z":
            if flags.contains(.shift) {
                if typing, let typingUndo, typingUndo.canRedo {
                    typingUndo.redo()
                } else {
                    model.redo()
                }
            } else if typing, let typingUndo, typingUndo.canUndo {
                typingUndo.undo()
            } else {
                model.undo()
            }
            return true
        case "s":
            model.finish(.save)
            return true
        case "\r":
            if typing {
                model.endTextEditing()
                _ = window?.makeFirstResponder(canvas)
            } else {
                model.finish(.copy)
            }
            return true
        case "c" where !typing:
            model.finish(.copy)
            return true
        default:
            return false
        }
    }

    private func finish(_ action: AnnotationEditorModel.Finish) {
        guard !isFinishing else { return }
        switch action {
        case .cancel:
            guard confirmDiscard() else { return }
            isFinishing = true
            window?.close()
            onDone(.cancel, nil)
        case .copy, .save:
            isFinishing = true
            Task {
                let image = await model.rendered()
                window?.close()
                onDone(action, image)
            }
        }
    }

    /// Esc or "Abbrechen" with marks on the picture: ask before throwing work away.
    private func confirmDiscard() -> Bool {
        guard model.hasMarkup, !AppController.isSelfTest else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Markierungen verwerfen?")
        alert.informativeText = String(localized: "Das Bildschirmfoto wird weder kopiert noch gesichert.")
        alert.addButton(withTitle: String(localized: "Verwerfen"))
        alert.addButton(withTitle: String(localized: "Weiter markieren"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isFinishing {
            return true
        }
        guard confirmDiscard() else { return false }
        isFinishing = true
        onDone(.cancel, nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        if NSColorPanel.sharedColorPanelExists {
            NSColorPanel.shared.orderOut(nil)
        }
        FocusReturn.windowWillClose(window)
        onClose?()
    }
}

/// Gives the editor the ⌘ keys before the main menu does.
final class AnnotationEditorWindow: NSWindow {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
