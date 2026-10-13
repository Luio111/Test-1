import Foundation

/// Where a selection came from.
public enum SelectionOrigin: Sendable, Equatable {
    case free
    case candidate(SnapCandidate)
}

/// The one-line status under the selection.
public enum ScreenshotStatus: Sendable, Equatable {
    case none
    case extending
    case sections(StitchInfo)
    case endReached
    /// The content under the selection did not move.
    case noScroll
    /// The frame could not be joined; ↓ tries again.
    case noOverlapRetry
    /// Joined twice without success; what exists is kept.
    case noOverlapStop
    case capReached
    case needsAccessibility
    /// Esc pressed once with sections: the second Esc discards them.
    case escArmed(sections: Int)
}

/// What VoiceOver should say.
public enum ScreenshotAnnouncement: Sendable, Equatable {
    case selection(width: Int, height: Int)
    case sections(Int)
}

/// What the overlay has to do after an input. The machine never touches the
/// screen itself (ROADMAP §1.7 style, like `HoldGestureStateMachine`).
public enum ScreenshotEffect: Sendable, Equatable {
    /// Find the snap rungs under the pointer (window list, region map).
    case requestCandidates(CGPoint, windowsOnly: Bool)
    case redraw
    /// Take a fresh single frame of this rect and finish.
    case capture(CGRect)
    /// Encode the stitched frames and finish.
    case finishStitched
    /// Scroll the content under the selection once and report `stepFinished`.
    case beginStep(ScrollDirection)
    /// Let the running step end and do not start another.
    case cancelStep
    /// Drop the newest stitched section and report `sliceRemoved`.
    case undoSlice
    case status(ScreenshotStatus)
    case announce(ScreenshotAnnouncement)
    /// Close the overlay.
    case dismiss
    case beep
}

public enum ScreenshotInput: Sendable, Equatable {
    case mouseMoved(CGPoint)
    case mouseDown(CGPoint, KeyModifiers)
    case mouseDragged(CGPoint, KeyModifiers)
    case mouseUp(CGPoint, KeyModifiers)
    case keyDown(ScreenshotKey, KeyModifiers, isRepeat: Bool)
    case keyUp(ScreenshotKey)
    case flagsChanged(KeyModifiers)
    /// Answer to `requestCandidates`, inner rung first.
    case candidatesChanged([SnapCandidate])
    case stepFinished(StepOutcome)
    /// Answer to `undoSlice`: what is left (nil: nothing stitched any more).
    case sliceRemoved(StitchInfo?)
    /// Another app's window took the key status.
    case lostKeyStatus
    /// ⌘⇧A pressed while the overlay is open.
    case hotKeyAgain
    /// Sleep, lock, a screen was added or removed.
    case externalCancel
}

public enum ScreenshotSelectionState: Sendable, Equatable {
    case idle
    case hovering(Hover)
    case pressed(Press)
    case dragging(Drag)
    case selected(Selection)
    case extending(Extension)
    case finished

    public struct Hover: Sendable, Equatable {
        public var pointer: CGPoint
        /// Rungs under the pointer, inner → outer; the screen is always last.
        public var chain: [SnapCandidate]
        /// The highlighted rung; nil when only the screen is left.
        public var index: Int?
        public var windowsOnly: Bool

        public init(pointer: CGPoint = .zero, chain: [SnapCandidate] = [], index: Int? = nil, windowsOnly: Bool = false) {
            self.pointer = pointer
            self.chain = chain
            self.index = index
            self.windowsOnly = windowsOnly
        }

        public var candidate: SnapCandidate? {
            guard let index, chain.indices.contains(index) else { return nil }
            return chain[index]
        }
    }

    /// The mouse is down; a click and a drag are still both possible.
    public struct Press: Sendable, Equatable {
        public var anchor: CGPoint
        public var candidate: SnapCandidate?
        public var modifiers: KeyModifiers
    }

    public struct Drag: Sendable, Equatable {
        public var anchor: CGPoint
        public var pointer: CGPoint
        public var rect: CGRect
        /// The screen the drag started on; the rect never leaves it.
        public var screen: CGRect
        public var modifiers: KeyModifiers
        /// Set while Space is held: the rect moves with the pointer instead of resizing.
        public var moveFrom: CGPoint?
        /// Resizing an existing selection by a corner.
        public var handle: SelectionHandle?
        public var base: Selection?
    }

    public struct Selection: Sendable, Equatable {
        public var rect: CGRect
        public var origin: SelectionOrigin
        public var screen: CGRect
        public var stitched: StitchInfo?
        public var escArmed: Bool

        public init(rect: CGRect, origin: SelectionOrigin, screen: CGRect, stitched: StitchInfo? = nil, escArmed: Bool = false) {
            self.rect = rect
            self.origin = origin
            self.screen = screen
            self.stitched = stitched
            self.escArmed = escArmed
        }
    }

    /// A scroll step is in flight.
    public struct Extension: Sendable, Equatable {
        public var selection: Selection
        public var direction: ScrollDirection
        /// ⌥↓: keeps stepping until the end.
        public var auto: Bool
        /// The arrow key is still down.
        public var keyHeld: Bool
        /// A key repeat arrived during the step: the user wants the next one.
        public var repeatSeen: Bool
        /// Esc, another key or a click: stop after this step.
        public var cancelRequested: Bool
    }
}

/// Which hint line the overlay shows.
public enum ScreenshotHint: Sendable, Equatable {
    case hovering
    case windowsOnly
    case dragging
    case selected
    case selectedStitched
    case extending
}

/// Decides what every mouse and key event in the screenshot overlay means
/// (ROADMAP M11, Docs/Design.md). Pure: no time, no screen, no hardware.
public struct ScreenshotSelectionMachine: Sendable {
    public private(set) var state: ScreenshotSelectionState = .idle
    private let screens: [CGRect]
    /// The hover to return to after a press, a drag or a discarded selection.
    private var hover = ScreenshotSelectionState.Hover()

    public init(screens: [CGRect]) {
        self.screens = screens
    }

    public var hint: ScreenshotHint? {
        switch state {
        case let .hovering(hover): hover.windowsOnly ? .windowsOnly : .hovering
        case .pressed: .hovering
        case .dragging: .dragging
        case let .selected(selection): selection.stitched == nil ? .selected : .selectedStitched
        case .extending: .extending
        case .idle, .finished: nil
        }
    }

    /// The overlay is up; the pointer position follows with the first `mouseMoved`.
    public mutating func start() -> [ScreenshotEffect] {
        hover = ScreenshotSelectionState.Hover()
        state = .hovering(hover)
        return [.redraw]
    }

    public mutating func handle(_ input: ScreenshotInput) -> [ScreenshotEffect] {
        switch input {
        case .hotKeyAgain, .lostKeyStatus, .externalCancel:
            return cancelEverything()
        default:
            break
        }
        switch state {
        case .idle, .finished:
            return []
        case let .hovering(hover):
            return handleHovering(hover, input)
        case let .pressed(press):
            return handlePressed(press, input)
        case let .dragging(drag):
            return handleDragging(drag, input)
        case let .selected(selection):
            return handleSelected(selection, input)
        case let .extending(extensionState):
            return handleExtending(extensionState, input)
        }
    }

    // MARK: Hovering

    private mutating func handleHovering(_ current: ScreenshotSelectionState.Hover, _ input: ScreenshotInput) -> [ScreenshotEffect] {
        var hover = current
        defer { self.hover = hover }
        switch input {
        case let .mouseMoved(point):
            hover.pointer = point
            state = .hovering(hover)
            // Stay on the current rung while the pointer is inside it (hysteresis).
            if let inner = hover.chain.first, inner.kind != .screen,
               inner.rect.insetBy(dx: -SnapPolicy.hysteresis, dy: -SnapPolicy.hysteresis).contains(point) {
                return []
            }
            return [.requestCandidates(point, windowsOnly: hover.windowsOnly)]
        case let .candidatesChanged(chain):
            hover.chain = chain
            hover.index = chain.count > 1 ? 0 : nil
            state = .hovering(hover)
            return [.redraw]
        case let .keyDown(.tab, modifiers, _):
            guard !hover.chain.isEmpty else { return [] }
            let delta = modifiers.contains(.shift) ? -1 : 1
            if let index = hover.index {
                hover.index = SnapCandidateChain.cycled(index, by: delta, count: hover.chain.count)
            } else {
                hover.index = delta > 0 ? 0 : hover.chain.count - 1
            }
            state = .hovering(hover)
            return [.redraw]
        case .keyDown(.space, _, isRepeat: false):
            hover.windowsOnly.toggle()
            hover.chain = []
            hover.index = nil
            state = .hovering(hover)
            return [.redraw, .requestCandidates(hover.pointer, windowsOnly: hover.windowsOnly)]
        case let .mouseDown(point, modifiers):
            hover.pointer = point
            state = .pressed(ScreenshotSelectionState.Press(anchor: point, candidate: hover.candidate, modifiers: modifiers))
            return []
        case let .keyDown(key, modifiers, isRepeat: false) where key == .down || key == .up:
            guard let candidate = hover.candidate else { return [.beep] }
            let selection = ScreenshotSelectionState.Selection(
                rect: candidate.rect,
                origin: .candidate(candidate),
                screen: screenFrame(for: candidate.rect)
            )
            return beginExtending(selection, direction: key == .down ? .down : .up, auto: modifiers.contains(.option))
        case .keyDown(.confirm, _, _):
            guard let candidate = hover.candidate else { return [.beep] }
            state = .finished
            return [.capture(candidate.rect)]
        case .keyDown(.escape, _, _):
            return cancelEverything()
        default:
            return []
        }
    }

    // MARK: Pressed

    private mutating func handlePressed(_ current: ScreenshotSelectionState.Press, _ input: ScreenshotInput) -> [ScreenshotEffect] {
        var press = current
        switch input {
        case let .mouseDragged(point, modifiers):
            guard distance(press.anchor, point) > ScreenshotGeometry.dragThreshold else { return [] }
            let screen = screenFrame(containing: press.anchor)
            let drag = ScreenshotSelectionState.Drag(
                anchor: press.anchor,
                pointer: point,
                rect: freeRect(anchor: press.anchor, pointer: point, modifiers: modifiers, screen: screen),
                screen: screen,
                modifiers: modifiers,
                moveFrom: nil,
                handle: nil,
                base: nil
            )
            state = .dragging(drag)
            return [.redraw]
        case let .mouseUp(point, modifiers):
            if distance(press.anchor, point) <= ScreenshotGeometry.dragThreshold {
                guard let candidate = press.candidate else {
                    state = .hovering(hover)
                    return [.beep]
                }
                if modifiers.contains(.option) {
                    return select(rect: candidate.rect, origin: .candidate(candidate))
                }
                state = .finished
                return [.capture(candidate.rect)]
            }
            let screen = screenFrame(containing: press.anchor)
            return endDrag(rect: freeRect(anchor: press.anchor, pointer: point, modifiers: modifiers, screen: screen), pointer: point)
        case let .flagsChanged(modifiers):
            press.modifiers = modifiers
            state = .pressed(press)
            return []
        case .keyDown(.escape, _, _):
            return cancelEverything()
        default:
            return []
        }
    }

    // MARK: Dragging

    private mutating func handleDragging(_ current: ScreenshotSelectionState.Drag, _ input: ScreenshotInput) -> [ScreenshotEffect] {
        var drag = current
        switch input {
        case let .mouseDragged(point, modifiers):
            drag.pointer = point
            drag.modifiers = modifiers
            if let handle = drag.handle, let base = drag.base {
                drag.rect = ScreenshotGeometry.resized(base.rect, handle: handle, to: point, within: drag.screen)
            } else if let from = drag.moveFrom {
                drag.rect = ScreenshotGeometry.moved(drag.rect, dx: point.x - from.x, dy: point.y - from.y, within: drag.screen)
                drag.moveFrom = point
            } else {
                drag.rect = freeRect(anchor: drag.anchor, pointer: point, modifiers: modifiers, screen: drag.screen)
            }
            state = .dragging(drag)
            return [.redraw]
        case let .flagsChanged(modifiers):
            drag.modifiers = modifiers
            if drag.handle == nil, drag.moveFrom == nil {
                drag.rect = freeRect(anchor: drag.anchor, pointer: drag.pointer, modifiers: modifiers, screen: drag.screen)
            }
            state = .dragging(drag)
            return [.redraw]
        case .keyDown(.space, _, isRepeat: false):
            if drag.handle == nil {
                drag.moveFrom = drag.pointer
                state = .dragging(drag)
            }
            return []
        case .keyUp(.space):
            if drag.moveFrom != nil {
                // Resizing continues from the moved rect: the anchor is the corner away from the pointer.
                drag.moveFrom = nil
                drag.anchor = CGPoint(
                    x: drag.pointer.x >= drag.rect.midX ? drag.rect.minX : drag.rect.maxX,
                    y: drag.pointer.y >= drag.rect.midY ? drag.rect.minY : drag.rect.maxY
                )
                state = .dragging(drag)
            }
            return []
        case let .mouseUp(point, modifiers):
            if let handle = drag.handle, var base = drag.base {
                let rect = ScreenshotGeometry.resized(base.rect, handle: handle, to: point, within: drag.screen)
                if rect.width >= ScreenshotGeometry.minimumSelection.width, rect.height >= ScreenshotGeometry.minimumSelection.height {
                    base.rect = rect
                }
                state = .selected(base)
                return [.redraw, .announce(.selection(width: Int(base.rect.width.rounded()), height: Int(base.rect.height.rounded())))]
            }
            let rect = drag.moveFrom != nil
                ? drag.rect
                : freeRect(anchor: drag.anchor, pointer: point, modifiers: modifiers, screen: drag.screen)
            return endDrag(rect: rect, pointer: point)
        case .keyDown(.escape, _, _):
            if let base = drag.base {
                state = .selected(base)
                return [.redraw]
            }
            return cancelEverything()
        default:
            return []
        }
    }

    // MARK: Selected

    private mutating func handleSelected(_ current: ScreenshotSelectionState.Selection, _ input: ScreenshotInput) -> [ScreenshotEffect] {
        var selection = current
        var effects: [ScreenshotEffect] = []
        // Anything but a second Esc disarms the pending discard.
        if selection.escArmed, input != .keyDown(.escape, [], isRepeat: false) {
            if case .keyDown(.escape, _, _) = input {} else {
                selection.escArmed = false
                state = .selected(selection)
                effects.append(.status(selection.stitched.map { .sections($0) } ?? .none))
            }
        }
        switch input {
        case let .mouseDown(point, modifiers):
            if let handle = ScreenshotGeometry.handle(at: point, in: selection.rect) {
                state = .dragging(ScreenshotSelectionState.Drag(
                    anchor: point,
                    pointer: point,
                    rect: selection.rect,
                    screen: selection.screen,
                    modifiers: modifiers,
                    moveFrom: nil,
                    handle: handle,
                    base: selection
                ))
                return effects + [.redraw]
            }
            if selection.rect.contains(point) {
                return effects + finish(selection)
            }
            hover.pointer = point
            hover.chain = []
            hover.index = nil
            state = .pressed(ScreenshotSelectionState.Press(anchor: point, candidate: nil, modifiers: modifiers))
            return effects + [.redraw, .status(.none)]
        case .keyDown(.confirm, _, _):
            return effects + finish(selection)
        case let .keyDown(key, modifiers, _) where key.isArrow && modifiers.contains(.command):
            let step: CGFloat = modifiers.contains(.shift) ? 10 : 1
            selection.rect = ScreenshotGeometry.nudged(selection.rect, key: key, step: step, within: selection.screen)
            state = .selected(selection)
            return effects + [.redraw]
        case let .keyDown(key, modifiers, isRepeat: false) where key == .down || key == .up:
            return effects + beginExtending(selection, direction: key == .down ? .down : .up, auto: modifiers.contains(.option))
        case .keyDown(.delete, _, _):
            return effects + (selection.stitched != nil ? [.undoSlice] : [])
        case let .sliceRemoved(info):
            selection.stitched = info
            state = .selected(selection)
            return effects + [.redraw, .status(info.map { .sections($0) } ?? .none)]
        case .keyDown(.escape, _, _):
            guard let stitched = selection.stitched else {
                return effects + backToHovering()
            }
            if selection.escArmed {
                return effects + backToHovering()
            }
            selection.escArmed = true
            state = .selected(selection)
            return effects + [.status(.escArmed(sections: stitched.sections))]
        case let .mouseMoved(point):
            hover.pointer = point
            return effects
        default:
            return effects
        }
    }

    // MARK: Extending

    private mutating func handleExtending(_ current: ScreenshotSelectionState.Extension, _ input: ScreenshotInput) -> [ScreenshotEffect] {
        var extensionState = current
        let directionKey: ScreenshotKey = extensionState.direction == .down ? .down : .up
        switch input {
        case let .stepFinished(outcome):
            var selection = extensionState.selection
            var effects: [ScreenshotEffect] = [.redraw]
            var goOn = false
            switch outcome {
            case let .appended(_, info):
                selection.stitched = info
                effects += [.status(.sections(info)), .announce(.sections(info.sections))]
                goOn = extensionState.auto || (extensionState.keyHeld && extensionState.repeatSeen)
            case let .noMovement(first):
                effects.append(.status(first ? .noScroll : (selection.stitched.map { .sections($0) } ?? .none)))
                goOn = extensionState.auto && !first
            case .endReached:
                effects.append(.status(.endReached))
            case let .stalled(final):
                effects.append(.status(final ? .noOverlapStop : .noOverlapRetry))
                goOn = extensionState.auto && !final
            case .capReached:
                effects.append(.status(.capReached))
            }
            if goOn, !extensionState.cancelRequested {
                extensionState.selection = selection
                extensionState.repeatSeen = false
                state = .extending(extensionState)
                return effects + [.beginStep(extensionState.direction)]
            }
            state = .selected(selection)
            return effects
        case .keyDown(directionKey, _, isRepeat: true):
            extensionState.repeatSeen = true
            state = .extending(extensionState)
            return []
        case .keyUp(directionKey):
            extensionState.keyHeld = false
            state = .extending(extensionState)
            return []
        case .keyDown, .mouseDown:
            guard !extensionState.cancelRequested else { return [] }
            extensionState.cancelRequested = true
            extensionState.auto = false
            state = .extending(extensionState)
            return [.cancelStep]
        default:
            return []
        }
    }

    // MARK: Helpers

    private mutating func beginExtending(_ selection: ScreenshotSelectionState.Selection, direction: ScrollDirection, auto: Bool) -> [ScreenshotEffect] {
        var selection = selection
        selection.escArmed = false
        state = .extending(ScreenshotSelectionState.Extension(
            selection: selection,
            direction: direction,
            auto: auto,
            keyHeld: true,
            repeatSeen: false,
            cancelRequested: false
        ))
        return [.redraw, .status(.extending), .beginStep(direction)]
    }

    private mutating func select(rect: CGRect, origin: SelectionOrigin) -> [ScreenshotEffect] {
        let selection = ScreenshotSelectionState.Selection(rect: rect, origin: origin, screen: screenFrame(for: rect))
        state = .selected(selection)
        return [.redraw, .announce(.selection(width: Int(rect.width.rounded()), height: Int(rect.height.rounded())))]
    }

    private mutating func endDrag(rect: CGRect, pointer: CGPoint) -> [ScreenshotEffect] {
        if rect.width >= ScreenshotGeometry.minimumSelection.width, rect.height >= ScreenshotGeometry.minimumSelection.height {
            return select(rect: rect, origin: .free)
        }
        hover.pointer = pointer
        state = .hovering(hover)
        return [.redraw, .requestCandidates(pointer, windowsOnly: hover.windowsOnly)]
    }

    private mutating func finish(_ selection: ScreenshotSelectionState.Selection) -> [ScreenshotEffect] {
        state = .finished
        return [selection.stitched != nil ? .finishStitched : .capture(selection.rect)]
    }

    private mutating func backToHovering() -> [ScreenshotEffect] {
        hover.chain = []
        hover.index = nil
        state = .hovering(hover)
        return [.redraw, .status(.none), .requestCandidates(hover.pointer, windowsOnly: hover.windowsOnly)]
    }

    private mutating func cancelEverything() -> [ScreenshotEffect] {
        let wasExtending: Bool
        if case .extending = state { wasExtending = true } else { wasExtending = false }
        state = .idle
        return wasExtending ? [.cancelStep, .dismiss] : [.dismiss]
    }

    private func freeRect(anchor: CGPoint, pointer: CGPoint, modifiers: KeyModifiers, screen: CGRect) -> CGRect {
        ScreenshotGeometry.clamp(
            ScreenshotGeometry.dragRect(anchor: anchor, current: pointer, square: modifiers.contains(.shift), fromCenter: modifiers.contains(.option)),
            to: screen
        )
    }

    private func screenFrame(containing point: CGPoint) -> CGRect {
        ScreenshotGeometry.screen(containing: point, in: screens) ?? screens.first ?? .zero
    }

    private func screenFrame(for rect: CGRect) -> CGRect {
        screenFrame(containing: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        max(abs(a.x - b.x), abs(a.y - b.y))
    }
}
