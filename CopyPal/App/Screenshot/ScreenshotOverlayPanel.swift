import AppKit
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// One borderless panel per screen for the screenshot session (ROADMAP M11): shows the
/// frozen frame dimmed, the snap candidate, the selection and the hint capsules, and
/// forwards mouse events as `ScreenshotInput`. Non-activating, so the app the user is
/// working in stays in front and gets the focus back when the overlay closes.
final class ScreenshotOverlayPanel: NSPanel {
    let overlayView: ScreenshotOverlayView
    /// The screen's frame in AppKit coordinates; the panel covers it exactly.
    let screenFrame: CGRect

    init(screenFrame: CGRect, view: ScreenshotOverlayView) {
        overlayView = view
        self.screenFrame = screenFrame
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = .notchOverlay
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        contentView = view
        setFrame(screenFrame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// What one overlay draws, in the coordinates of its own view (AppKit, origin bottom
/// left of that screen).
struct OverlayScene: Equatable {
    var frozen: ImageBox?
    /// The highlighted snap candidate.
    var candidate: CGRect?
    var selection: CGRect?
    var handlesVisible = false
    /// The newest frame while extending, drawn inside the selection.
    var live: ImageBox?
    var sizeText: String?
    var statusText: String?
    var hints: OverlayHints?
    /// The buttons under a finished selection (they carry the size then).
    var actions: ScreenshotActionBar.Content?
    var coordinatesText: String?
    var pointer: CGPoint?
    /// Lab: every detected element and panel box.
    var debugBoxes: [CGRect] = []

    static func == (lhs: OverlayScene, rhs: OverlayScene) -> Bool {
        lhs.frozen === rhs.frozen && lhs.candidate == rhs.candidate && lhs.selection == rhs.selection
            && lhs.handlesVisible == rhs.handlesVisible && lhs.live === rhs.live && lhs.sizeText == rhs.sizeText
            && lhs.statusText == rhs.statusText && lhs.hints == rhs.hints && lhs.actions == rhs.actions
            && lhs.coordinatesText == rhs.coordinatesText && lhs.pointer == rhs.pointer && lhs.debugBoxes == rhs.debugBoxes
    }
}

/// One entry of the hint bar: the key or mouse action in a keycap, then what it does.
struct OverlayHint: Hashable {
    var keys: String
    var label: String
}

/// The hint bar at the bottom centre: what to do now, and below it, smaller, what
/// else is possible.
struct OverlayHints: Equatable {
    var primary: [OverlayHint] = []
    var secondary: [OverlayHint] = []

    /// What VoiceOver reads.
    var spoken: String {
        (primary + secondary).map { "\($0.keys) \($0.label)" }.joined(separator: ", ")
    }
}

/// Layer-backed drawing of the scene plus a SwiftUI layer for the capsules, which
/// never takes mouse events, and the buttons under a finished selection, which do.
/// Keys are handled by the controller's event monitor.
final class ScreenshotOverlayView: NSView {
    var onInput: ((ScreenshotInput) -> Void)?
    /// The pointer arrived on this screen: the controller makes this panel key.
    var onEntered: (() -> Void)?
    /// A button under the selection was clicked.
    var onAction: ((ScreenshotAction) -> Void)? {
        didSet { actionBar.onAction = onAction }
    }

    private let frozenLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let debugLayer = CAShapeLayer()
    private let candidateLayer = CAShapeLayer()
    private let liveLayer = CALayer()
    private let selectionLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let chrome: PassthroughHostingView<OverlayChrome>
    private let actionBar = ScreenshotActionBar(frame: .zero)
    private var trackingArea: NSTrackingArea?
    private var scene = OverlayScene()
    private let animates: Bool

    override init(frame frameRect: NSRect) {
        animates = AppSettings.animatePopup && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        chrome = PassthroughHostingView(rootView: OverlayChrome(scene: ChromeScene(size: frameRect.size)))
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        layer.backgroundColor = NSColor.clear.cgColor

        frozenLayer.contentsGravity = .resize
        frozenLayer.frame = bounds
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        dimLayer.fillRule = .evenOdd
        debugLayer.fillColor = nil
        debugLayer.strokeColor = NSColor.systemGreen.withAlphaComponent(0.6).cgColor
        debugLayer.lineWidth = 1
        // Theme.Colors.accent (#2383E2), the overlay's only accent (Docs/Design.md).
        let accent = NSColor(hex: 0x2383E2)
        candidateLayer.fillColor = accent.withAlphaComponent(0.08).cgColor
        candidateLayer.strokeColor = accent.cgColor
        candidateLayer.lineWidth = 1.5
        liveLayer.contentsGravity = .resize
        liveLayer.isHidden = true
        selectionLayer.fillColor = nil
        selectionLayer.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        selectionLayer.lineWidth = 1
        handlesLayer.fillColor = NSColor.white.withAlphaComponent(0.92).cgColor
        handlesLayer.strokeColor = NSColor.black.cgColor
        handlesLayer.lineWidth = 0.5
        for sublayer in [frozenLayer, dimLayer, debugLayer, candidateLayer, liveLayer, selectionLayer, handlesLayer] {
            sublayer.actions = ["contents": NSNull(), "hidden": NSNull(), "frame": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer.addSublayer(sublayer)
        }

        chrome.frame = bounds
        chrome.autoresizingMask = [.width, .height]
        addSubview(chrome)
        actionBar.isHidden = true
        addSubview(actionBar)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Bildschirmfoto-Auswahl"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [frozenLayer, dimLayer, debugLayer, candidateLayer, liveLayer, selectionLayer, handlesLayer] {
            sublayer.contentsScale = scale
        }
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) {
        onEntered?()
        onInput?(.mouseMoved(global(event)))
    }

    override func mouseMoved(with event: NSEvent) {
        onInput?(.mouseMoved(global(event)))
    }

    override func mouseDown(with event: NSEvent) {
        onInput?(.mouseDown(global(event), KeyModifiers(event.modifierFlags)))
    }

    override func mouseDragged(with event: NSEvent) {
        onInput?(.mouseDragged(global(event), KeyModifiers(event.modifierFlags)))
    }

    override func mouseUp(with event: NSEvent) {
        onInput?(.mouseUp(global(event), KeyModifiers(event.modifierFlags)))
    }

    override func rightMouseDown(with event: NSEvent) {
        // A right click is no selection; nothing to do.
    }

    /// The event's location in global AppKit coordinates.
    private func global(_ event: NSEvent) -> CGPoint {
        guard let window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    // MARK: Drawing

    func apply(_ newScene: OverlayScene) {
        guard newScene != scene else { return }
        // The candidate frame and the undimmed hole slide together from one rung to
        // the next; a frame that appears or follows a selection does not fly in.
        let slides = animates && newScene.selection == nil && scene.selection == nil
            && scene.candidate != nil && newScene.candidate != nil && newScene.candidate != scene.candidate
        scene = newScene
        let bounds = self.bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frozenLayer.frame = bounds
        frozenLayer.contents = newScene.frozen?.image
        dimLayer.frame = bounds
        debugLayer.frame = bounds
        candidateLayer.frame = bounds
        selectionLayer.frame = bounds
        handlesLayer.frame = bounds

        let hole = newScene.selection ?? newScene.candidate
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        if let hole, !hole.isEmpty {
            dimPath.addRect(hole)
        }
        if !slides {
            dimLayer.path = dimPath
        }

        let debugPath = CGMutablePath()
        for box in newScene.debugBoxes {
            debugPath.addRect(box)
        }
        debugLayer.path = newScene.debugBoxes.isEmpty ? nil : debugPath

        selectionLayer.path = newScene.selection.map { CGPath(rect: $0.insetBy(dx: 0.5, dy: 0.5), transform: nil) }
        if newScene.handlesVisible, let selection = newScene.selection {
            let handles = CGMutablePath()
            for handle in SelectionHandle.allCases {
                let corner = handle.corner(of: selection)
                handles.addEllipse(in: CGRect(x: corner.x - 3, y: corner.y - 3, width: 6, height: 6))
            }
            handlesLayer.path = handles
        } else {
            handlesLayer.path = nil
        }

        if let live = newScene.live, let selection = newScene.selection {
            liveLayer.frame = selection
            liveLayer.contents = live.image
            liveLayer.isHidden = false
        } else {
            liveLayer.isHidden = true
            liveLayer.contents = nil
        }
        CATransaction.commit()

        // Only the candidate frame and its hole move (150 ms ease-out); nothing else animates.
        CATransaction.begin()
        CATransaction.setDisableActions(!slides)
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if slides {
            dimLayer.path = dimPath
        }
        if let candidate = newScene.candidate, newScene.selection == nil {
            let rect = candidate.insetBy(dx: 0.75, dy: 0.75)
            // CGPath traps when a corner radius exceeds half a side.
            let radius = max(min(4, rect.width / 2, rect.height / 2), 0)
            candidateLayer.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            candidateLayer.isHidden = false
        } else {
            candidateLayer.isHidden = true
        }
        CATransaction.commit()

        chrome.rootView = OverlayChrome(scene: ChromeScene(
            size: bounds.size,
            selection: newScene.selection,
            sizeText: newScene.sizeText,
            statusText: newScene.statusText,
            hints: newScene.hints,
            coordinatesText: newScene.coordinatesText,
            pointer: newScene.pointer
        ))

        if let actions = newScene.actions, let selection = newScene.selection {
            actionBar.update(actions)
            actionBar.layoutSubtreeIfNeeded()
            actionBar.frame = Self.actionBarFrame(size: actionBar.fittingSize, selection: selection, in: bounds)
            actionBar.isHidden = false
        } else {
            actionBar.isHidden = true
        }
    }

    /// Under the selection; above it when the hint bar at the bottom is in the way;
    /// inside its lower edge when the selection fills the screen.
    static func actionBarFrame(size: CGSize, selection: CGRect, in bounds: CGRect) -> CGRect {
        let gap: CGFloat = 8
        // Hint bar and status capsule at the bottom centre, menu bar at the top.
        let bottomReserve: CGFloat = 110
        let topReserve: CGFloat = 40
        var y = selection.minY - gap - size.height
        if y < bounds.minY + bottomReserve {
            let above = selection.maxY + gap
            if above + size.height <= bounds.maxY - topReserve {
                y = above
            } else {
                y = max(selection.minY + gap, bounds.minY + bottomReserve)
            }
        }
        let x = min(max(selection.midX - size.width / 2, bounds.minX + gap), bounds.maxX - gap - size.width)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// The buttons shown under the selection on this screen.
    var visibleActions: [ScreenshotAction] {
        actionBar.isHidden ? [] : actionBar.actions
    }

    /// `action`'s button in this view's coordinates, when the bar is shown.
    func actionButtonFrame(for action: ScreenshotAction) -> CGRect? {
        guard !actionBar.isHidden, let frame = actionBar.buttonFrame(for: action) else { return nil }
        return actionBar.convert(frame, to: self)
    }
}

/// SwiftUI content that never takes a click: everything goes to the view below.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct ChromeScene: Equatable {
    var size: CGSize
    var selection: CGRect?
    var sizeText: String?
    var statusText: String?
    var hints: OverlayHints?
    var coordinatesText: String?
    var pointer: CGPoint?
}

/// The capsules: size under the selection, status and the hint bar at the bottom
/// centre, coordinates next to the pointer when nothing is highlighted (Docs/Design.md).
struct OverlayChrome: View {
    let scene: ChromeScene

    private let capsuleHeight: CGFloat = 26

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let sizeText = scene.sizeText, let selection = scene.selection {
                capsule(sizeText, font: Theme.Typography.mono, color: Theme.Notch.textPrimary)
                    .position(x: selection.midX, y: sizeLabelY(for: selection))
            }
            // Anchored at the bottom: the hint stays put when a status line appears.
            VStack(spacing: Theme.Spacing.s) {
                if let statusText = scene.statusText {
                    capsule(statusText, font: Theme.Typography.label, color: Theme.Notch.textPrimary)
                }
                if let hints = scene.hints {
                    hintBar(hints)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 43)
            if let coordinatesText = scene.coordinatesText, let pointer = scene.pointer {
                capsule(coordinatesText, font: Theme.Typography.mono, color: Theme.Notch.textSecondary)
                    .position(x: min(pointer.x + 56, scene.size.width - 60), y: min(flipped(pointer.y) + 28, scene.size.height - 20))
            }
        }
        .frame(width: scene.size.width, height: scene.size.height)
        .allowsHitTesting(false)
    }

    private func flipped(_ y: CGFloat) -> CGFloat {
        scene.size.height - y
    }

    /// 6 pt under the selection; above it when there is no room below.
    private func sizeLabelY(for selection: CGRect) -> CGFloat {
        let below = flipped(selection.minY) + 6 + capsuleHeight / 2
        if below + capsuleHeight / 2 <= scene.size.height - 8 {
            return below
        }
        return flipped(selection.maxY) - 6 - capsuleHeight / 2
    }

    private func hintBar(_ hints: OverlayHints) -> some View {
        VStack(spacing: Theme.Spacing.xs + Theme.Spacing.xxs) {
            if !hints.primary.isEmpty {
                hintRow(hints.primary, prominent: true)
            }
            if !hints.secondary.isEmpty {
                hintRow(hints.secondary, prominent: false)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.Notch.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                        .strokeBorder(Theme.Notch.divider)
                )
        )
        .fixedSize()
    }

    /// Keycap, then what it does. The first row is what to do now (white 92 %), the
    /// second the extras (smaller, white 60 %).
    private func hintRow(_ hints: [OverlayHint], prominent: Bool) -> some View {
        HStack(spacing: prominent ? Theme.Spacing.l : Theme.Spacing.m) {
            ForEach(hints, id: \.self) { hint in
                HStack(spacing: Theme.Spacing.xs + Theme.Spacing.xxs) {
                    Text(verbatim: hint.keys)
                        .font(.system(size: prominent ? 12 : 11, weight: .medium))
                        .foregroundStyle(Theme.Notch.textPrimary)
                        .padding(.horizontal, Theme.Spacing.xs + 1)
                        .padding(.vertical, 1)
                        .background(Theme.Notch.control, in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
                    Text(verbatim: hint.label)
                        .font(.system(size: prominent ? 12 : 11))
                        .foregroundStyle(prominent ? Theme.Notch.textPrimary : Theme.Notch.textSecondary)
                }
            }
        }
    }

    private func capsule(_ text: String, font: Font, color: Color) -> some View {
        Text(verbatim: text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: capsuleHeight)
            .background(Theme.Notch.fill, in: Capsule())
            .fixedSize()
    }
}
