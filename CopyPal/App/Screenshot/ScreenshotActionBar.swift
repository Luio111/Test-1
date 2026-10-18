import AppKit
import SwiftUI

/// What the buttons under a finished selection do; each one also has its key.
enum ScreenshotAction: Sendable {
    case copyImage
    case copyText
    case save
    case extend
    case undoSection
    case discard
}

/// The buttons under a finished selection (Docs/Design.md, "Bildschirmfoto-Overlay"):
/// the size, "Bild kopieren", "Text kopieren", "Sichern", "Erweitern" (once stitched
/// "Weiter" and "Abschnitt zurück") and discard. Every button shows its key, so the
/// keyboard way is learned on the side. AppKit lays the buttons out, so each has a
/// frame the overlay and the self-test know.
final class ScreenshotActionBar: NSView {
    struct Content: Equatable {
        var sizeText: String
        var stitched: Bool
    }

    struct Item: Equatable {
        var action: ScreenshotAction
        /// Empty: the symbol alone.
        var title: String
        var symbol: String
        var keys: String
        var prominent = false
        var accessibilityLabel: String
    }

    var onAction: ((ScreenshotAction) -> Void)?
    private(set) var content: Content?
    private let stack = NSStackView()
    private let sizeLabel = NSTextField(labelWithString: "")
    private var buttons: [ActionButtonHost] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = Theme.Radius.panel
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        sizeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sizeLabel.textColor = NSColor.white.withAlphaComponent(0.6)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Theme.Spacing.xs
        stack.edgeInsets = NSEdgeInsets(top: Theme.Spacing.xs, left: Theme.Spacing.m, bottom: Theme.Spacing.xs, right: Theme.Spacing.xs)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(String(localized: "Aktionen für die Auswahl"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    var actions: [ScreenshotAction] {
        buttons.compactMap { $0.item?.action }
    }

    // A click between the buttons must not reach the overlay: it would start a new
    // selection.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    func update(_ content: Content) {
        guard content != self.content else { return }
        let rebuild = content.stitched != self.content?.stitched
        self.content = content
        sizeLabel.stringValue = content.sizeText
        if rebuild {
            rebuildButtons(stitched: content.stitched)
        }
    }

    /// The frame of `action`'s button in this view's coordinates.
    func buttonFrame(for action: ScreenshotAction) -> CGRect? {
        layoutSubtreeIfNeeded()
        guard let button = buttons.first(where: { $0.item?.action == action }) else { return nil }
        return button.convert(button.bounds, to: self)
    }

    private func rebuildButtons(stitched: Bool) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttons = Self.items(stitched: stitched).map { item in
            let button = ActionButtonHost(rootView: ActionButtonLabel(item: item))
            button.configure(item)
            button.onPress = { [weak self] action in
                self?.onAction?(action)
            }
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            return button
        }
        stack.addArrangedSubview(sizeLabel)
        stack.setCustomSpacing(Theme.Spacing.m, after: sizeLabel)
        for button in buttons {
            stack.addArrangedSubview(button)
        }
    }

    static func items(stitched: Bool) -> [Item] {
        var items = [
            Item(action: .copyImage, title: String(localized: "Bild kopieren"), symbol: "photo", keys: "⏎", prominent: true,
                 accessibilityLabel: String(localized: "Bild kopieren")),
            Item(action: .copyText, title: String(localized: "Text kopieren"), symbol: "text.viewfinder", keys: "⇧⏎",
                 accessibilityLabel: String(localized: "Text kopieren")),
            Item(action: .save, title: String(localized: "Sichern"), symbol: "square.and.arrow.down", keys: "⌘S",
                 accessibilityLabel: String(localized: "Kopieren und als Datei sichern")),
        ]
        if stitched {
            items.append(Item(action: .extend, title: String(localized: "Weiter"), symbol: "arrow.down.to.line", keys: "↓",
                              accessibilityLabel: String(localized: "Weiter scrollen und anfügen")))
            items.append(Item(action: .undoSection, title: String(localized: "Abschnitt zurück"), symbol: "arrow.uturn.backward", keys: "⌫",
                              accessibilityLabel: String(localized: "Letzten Abschnitt entfernen")))
        } else {
            items.append(Item(action: .extend, title: String(localized: "Erweitern"), symbol: "arrow.down.to.line", keys: "↓",
                              accessibilityLabel: String(localized: "Nach unten scrollen und anfügen")))
        }
        items.append(Item(action: .discard, title: "", symbol: "xmark", keys: "Esc",
                          accessibilityLabel: String(localized: "Auswahl verwerfen")))
        return items
    }
}

/// One button of the bar: SwiftUI draws it, AppKit handles hover, press and click,
/// so the overlay's key monitor and pointer tracking stay as they are.
final class ActionButtonHost: NSHostingView<ActionButtonLabel> {
    var onPress: ((ScreenshotAction) -> Void)?
    private(set) var item: ScreenshotActionBar.Item?
    private var hovered = false
    private var pressed = false
    private var trackingArea: NSTrackingArea?

    func configure(_ item: ScreenshotActionBar.Item) {
        self.item = item
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.accessibilityLabel)
        refresh()
    }

    private func refresh() {
        guard let item else { return }
        rootView = ActionButtonLabel(item: item, hovered: hovered, pressed: pressed)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        pressed = false
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != pressed {
            pressed = inside
            refresh()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        refresh()
        if inside, let item {
            onPress?(item.action)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let item else { return false }
        onPress?(item.action)
        return true
    }
}

struct ActionButtonLabel: View {
    let item: ScreenshotActionBar.Item
    var hovered = false
    var pressed = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs + Theme.Spacing.xxs) {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .medium))
            if !item.title.isEmpty {
                Text(verbatim: item.title)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(verbatim: item.keys)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(item.prominent ? 0.85 : 0.6))
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 1)
                .background(Color.white.opacity(item.prominent ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
        }
        .foregroundStyle(Theme.Notch.textPrimary)
        .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
        .frame(height: 28)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .fixedSize()
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    private var background: Color {
        if item.prominent {
            if pressed { return Theme.Colors.accentFillPressed }
            return hovered ? Theme.Colors.accentFillHover : Theme.Colors.accentFill
        }
        if pressed { return Color.white.opacity(0.2) }
        return hovered ? Theme.Notch.selection : Color.clear
    }
}
