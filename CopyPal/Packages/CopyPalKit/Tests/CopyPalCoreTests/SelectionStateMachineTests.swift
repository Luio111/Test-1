import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import CopyPalCore

private typealias State = ScreenshotSelectionState
private typealias Effect = ScreenshotEffect

struct SelectionStateMachineTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let second = CGRect(x: 1512, y: -98, width: 1920, height: 1080)
    private let window = WindowInfo(id: 7, frame: CGRect(x: 100, y: 100, width: 800, height: 600), ownerPID: 1)

    private var elementRect: CGRect { CGRect(x: 300, y: 500, width: 120, height: 40) }
    private var element: SnapCandidate { SnapCandidate(rect: elementRect, kind: .element) }
    private var panel: SnapCandidate { SnapCandidate(rect: CGRect(x: 200, y: 300, width: 400, height: 300), kind: .panel) }
    private var windowRung: SnapCandidate { SnapCandidate(rect: window.frame, kind: .window(id: 7)) }
    private var screenRung: SnapCandidate { SnapCandidate(rect: screen, kind: .screen) }
    private var chain: [SnapCandidate] { [element, panel, windowRung, screenRung] }

    /// A machine in `hovering` with the pointer on the element.
    private func hoveringMachine() -> ScreenshotSelectionMachine {
        var machine = ScreenshotSelectionMachine(screens: [screen, second])
        _ = machine.start()
        _ = machine.handle(.mouseMoved(CGPoint(x: 350, y: 520)))
        _ = machine.handle(.candidatesChanged(chain))
        return machine
    }

    private func selectedMachine(stitched: StitchInfo? = nil) -> ScreenshotSelectionMachine {
        var machine = hoveringMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 350, y: 520), []))
        _ = machine.handle(.mouseUp(CGPoint(x: 350, y: 520), .option))
        if let stitched {
            _ = machine.handle(.keyDown(.down, [], isRepeat: false))
            _ = machine.handle(.stepFinished(.appended(rows: 100, info: stitched)))
            _ = machine.handle(.keyUp(.down))
        }
        return machine
    }

    private func selection(_ machine: ScreenshotSelectionMachine) -> State.Selection? {
        if case let .selected(selection) = machine.state { return selection }
        return nil
    }

    // MARK: Hovering

    @Test func startHoversAndTheFirstMoveAsksForCandidates() {
        var machine = ScreenshotSelectionMachine(screens: [screen])
        let result1 = machine.start()
        #expect(result1 == [.redraw])
        #expect(machine.hint == .hovering)
        let effects = machine.handle(.mouseMoved(CGPoint(x: 10, y: 10)))
        #expect(effects == [.requestCandidates(CGPoint(x: 10, y: 10), windowsOnly: false)])
    }

    @Test func candidatesHighlightTheInnermostRung() {
        let machine = hoveringMachine()
        guard case let .hovering(hover) = machine.state else { return #expect(Bool(false)) }
        #expect(hover.index == 0)
        #expect(hover.candidate == element)
    }

    @Test func onlyTheScreenHighlightsNothingUntilTab() {
        var machine = ScreenshotSelectionMachine(screens: [screen])
        _ = machine.start()
        _ = machine.handle(.candidatesChanged([screenRung]))
        guard case let .hovering(hover) = machine.state else { return #expect(Bool(false)) }
        #expect(hover.index == nil)
        _ = machine.handle(.keyDown(.tab, [], isRepeat: false))
        guard case let .hovering(afterTab) = machine.state else { return #expect(Bool(false)) }
        #expect(afterTab.candidate == screenRung)
    }

    @Test func pointerInsideTheRungDoesNotAskAgain() {
        var machine = hoveringMachine()
        let result2 = machine.handle(.mouseMoved(CGPoint(x: 360, y: 530)))
        #expect(result2.isEmpty)
        let result3 = machine.handle(.mouseMoved(CGPoint(x: 40, y: 40)))
        #expect(result3 == [.requestCandidates(CGPoint(x: 40, y: 40), windowsOnly: false)])
    }

    @Test func tabWalksTheLadderAndWraps() {
        var machine = hoveringMachine()
        _ = machine.handle(.keyDown(.tab, [], isRepeat: false))
        _ = machine.handle(.keyDown(.tab, [], isRepeat: false))
        guard case let .hovering(two) = machine.state else { return #expect(Bool(false)) }
        #expect(two.candidate == windowRung)
        _ = machine.handle(.keyDown(.tab, [], isRepeat: false))
        _ = machine.handle(.keyDown(.tab, [], isRepeat: false))
        guard case let .hovering(wrapped) = machine.state else { return #expect(Bool(false)) }
        #expect(wrapped.candidate == element)
        _ = machine.handle(.keyDown(.tab, .shift, isRepeat: false))
        guard case let .hovering(back) = machine.state else { return #expect(Bool(false)) }
        #expect(back.candidate == screenRung)
    }

    @Test func spaceTogglesWindowsOnly() {
        var machine = hoveringMachine()
        let effects = machine.handle(.keyDown(.space, [], isRepeat: false))
        #expect(effects == [.redraw, .requestCandidates(CGPoint(x: 350, y: 520), windowsOnly: true)])
        #expect(machine.hint == .windowsOnly)
        _ = machine.handle(.keyDown(.space, [], isRepeat: false))
        #expect(machine.hint == .hovering)
    }

    @Test func escapeWhileHoveringDismisses() {
        var machine = hoveringMachine()
        let result4 = machine.handle(.keyDown(.escape, [], isRepeat: false))
        #expect(result4 == [.dismiss])
        #expect(machine.state == .idle)
        let result5 = machine.handle(.mouseMoved(.zero))
        #expect(result5.isEmpty)
    }

    @Test(arguments: [ScreenshotInput.hotKeyAgain, .lostKeyStatus, .externalCancel])
    func outsideEventsDismiss(input: ScreenshotInput) {
        var machine = hoveringMachine()
        let result6 = machine.handle(input)
        #expect(result6 == [.dismiss])
        #expect(machine.state == .idle)
    }

    // MARK: Click, drag

    @Test func clickOnACandidateCaptures() {
        var machine = hoveringMachine()
        let result7 = machine.handle(.mouseDown(CGPoint(x: 350, y: 520), []))
        #expect(result7.isEmpty)
        let result8 = machine.handle(.mouseUp(CGPoint(x: 352, y: 521), []))
        #expect(result8 == [.capture(elementRect)])
        #expect(machine.state == .finished)
    }

    @Test func clickWithoutCandidateBeeps() {
        var machine = ScreenshotSelectionMachine(screens: [screen])
        _ = machine.start()
        _ = machine.handle(.candidatesChanged([screenRung]))
        _ = machine.handle(.mouseDown(CGPoint(x: 10, y: 10), []))
        let result9 = machine.handle(.mouseUp(CGPoint(x: 10, y: 10), []))
        #expect(result9 == [.beep])
        #expect(machine.hint == .hovering)
    }

    @Test func optionClickKeepsTheCandidateEditable() {
        var machine = hoveringMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 350, y: 520), []))
        let effects = machine.handle(.mouseUp(CGPoint(x: 350, y: 520), .option))
        #expect(effects == [.redraw, .announce(.selection(width: 120, height: 40))])
        #expect(selection(machine)?.rect == elementRect)
        #expect(selection(machine)?.origin == .candidate(element))
        #expect(machine.hint == .selected)
    }

    @Test func returnWhileHoveringCaptures() {
        var machine = hoveringMachine()
        let result10 = machine.handle(.keyDown(.confirm, [], isRepeat: false))
        #expect(result10 == [.capture(elementRect)])
    }

    @Test func draggingDrawsAFreeRectAndSelectsOnRelease() {
        var machine = hoveringMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 100, y: 100), []))
        let result11 = machine.handle(.mouseDragged(CGPoint(x: 102, y: 102), []))
        #expect(result11.isEmpty)
        let result12 = machine.handle(.mouseDragged(CGPoint(x: 160, y: 140), []))
        #expect(result12 == [.redraw])
        #expect(machine.hint == .dragging)
        let effects = machine.handle(.mouseUp(CGPoint(x: 160, y: 140), []))
        #expect(effects == [.redraw, .announce(.selection(width: 60, height: 40))])
        #expect(selection(machine)?.rect == CGRect(x: 100, y: 100, width: 60, height: 40))
        #expect(selection(machine)?.origin == .free)
        #expect(selection(machine)?.screen == screen)
    }

    @Test func shiftAndOptionShapeTheDrag() {
        var machine = hoveringMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 100, y: 100), []))
        _ = machine.handle(.mouseDragged(CGPoint(x: 160, y: 120), .shift))
        guard case let .dragging(square) = machine.state else { return #expect(Bool(false)) }
        #expect(square.rect == CGRect(x: 100, y: 100, width: 60, height: 60))
        _ = machine.handle(.flagsChanged(.option))
        guard case let .dragging(centered) = machine.state else { return #expect(Bool(false)) }
        #expect(centered.rect == CGRect(x: 40, y: 80, width: 120, height: 40))
    }

    @Test func spaceMovesTheRectWhileDragging() {
        var machine = hoveringMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 100, y: 100), []))
        _ = machine.handle(.mouseDragged(CGPoint(x: 160, y: 140), []))
        _ = machine.handle(.keyDown(.space, [], isRepeat: false))
        _ = machine.handle(.mouseDragged(CGPoint(x: 170, y: 150), []))
        guard case let .dragging(moved) = machine.state else { return #expect(Bool(false)) }
        #expect(moved.rect == CGRect(x: 110, y: 110, width: 60, height: 40))
        _ = machine.handle(.keyUp(.space))
        _ = machine.handle(.mouseDragged(CGPoint(x: 180, y: 160), []))
        guard case let .dragging(resized) = machine.state else { return #expect(Bool(false)) }
        // Resizing continues from the moved rect's far corner.
        #expect(resized.rect == CGRect(x: 110, y: 110, width: 70, height: 50))
    }

    @Test func dragsStayOnTheStartScreen() {
        var machine = hoveringMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 1400, y: 100), []))
        _ = machine.handle(.mouseDragged(CGPoint(x: 1700, y: 300), []))
        guard case let .dragging(drag) = machine.state else { return #expect(Bool(false)) }
        #expect(drag.rect.maxX == screen.maxX)
    }

    @Test func tinyDragsReturnToHovering() {
        var machine = hoveringMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 100, y: 100), []))
        _ = machine.handle(.mouseDragged(CGPoint(x: 110, y: 110), []))
        let effects = machine.handle(.mouseUp(CGPoint(x: 102, y: 102), []))
        #expect(effects == [.redraw, .requestCandidates(CGPoint(x: 102, y: 102), windowsOnly: false)])
        #expect(machine.hint == .hovering)
    }

    @Test func escapeWhileDraggingDismisses() {
        var machine = hoveringMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 100, y: 100), []))
        _ = machine.handle(.mouseDragged(CGPoint(x: 160, y: 140), []))
        let result13 = machine.handle(.keyDown(.escape, [], isRepeat: false))
        #expect(result13 == [.dismiss])
    }

    // MARK: Selected

    @Test func handlesResizeTheSelection() {
        var machine = selectedMachine()
        // Top-right corner of the element rect (300…420 × 500…540).
        let result14 = machine.handle(.mouseDown(CGPoint(x: 418, y: 538), []))
        #expect(result14 == [.redraw])
        _ = machine.handle(.mouseDragged(CGPoint(x: 460, y: 560), []))
        _ = machine.handle(.mouseUp(CGPoint(x: 460, y: 560), []))
        #expect(selection(machine)?.rect == CGRect(x: 300, y: 500, width: 160, height: 60))
        #expect(selection(machine)?.origin == .candidate(element))
    }

    @Test func escapeWhileResizingKeepsTheSelection() {
        var machine = selectedMachine()
        _ = machine.handle(.mouseDown(CGPoint(x: 418, y: 538), []))
        _ = machine.handle(.mouseDragged(CGPoint(x: 460, y: 560), []))
        let result15 = machine.handle(.keyDown(.escape, [], isRepeat: false))
        #expect(result15 == [.redraw])
        #expect(selection(machine)?.rect == elementRect)
    }

    @Test func clickInsideCapturesClickOutsideStartsOver() {
        var inside = selectedMachine()
        let result16 = inside.handle(.mouseDown(CGPoint(x: 350, y: 520), []))
        #expect(result16 == [.capture(elementRect)])
        var outside = selectedMachine()
        let result17 = outside.handle(.mouseDown(CGPoint(x: 50, y: 50), []))
        #expect(result17 == [.redraw, .status(.none)])
        _ = outside.handle(.mouseDragged(CGPoint(x: 90, y: 90), []))
        _ = outside.handle(.mouseUp(CGPoint(x: 90, y: 90), []))
        #expect(selection(outside)?.rect == CGRect(x: 50, y: 50, width: 40, height: 40))
    }

    @Test func returnCapturesOrFinishesStitched() {
        var plain = selectedMachine()
        let result18 = plain.handle(.keyDown(.confirm, [], isRepeat: false))
        #expect(result18 == [.capture(elementRect)])
        var stitched = selectedMachine(stitched: StitchInfo(sections: 1, heightPixels: 300))
        let result19 = stitched.handle(.keyDown(.confirm, [], isRepeat: false))
        #expect(result19 == [.finishStitched])
    }

    @Test func commandArrowsNudge() {
        var machine = selectedMachine()
        _ = machine.handle(.keyDown(.right, .command, isRepeat: false))
        #expect(selection(machine)?.rect.minX == 301)
        _ = machine.handle(.keyDown(.up, [.command, .shift], isRepeat: false))
        #expect(selection(machine)?.rect.minY == 510)
        _ = machine.handle(.keyDown(.left, [.command, .shift], isRepeat: true))
        #expect(selection(machine)?.rect.minX == 291)
    }

    @Test func spaceAndTabDoNothingWhenSelected() {
        var machine = selectedMachine()
        let result20 = machine.handle(.keyDown(.space, [], isRepeat: false))
        #expect(result20.isEmpty)
        let result21 = machine.handle(.keyDown(.tab, [], isRepeat: false))
        #expect(result21.isEmpty)
        #expect(selection(machine)?.rect == elementRect)
    }

    @Test func escapeWithoutSectionsReturnsToHovering() {
        var machine = selectedMachine()
        let effects = machine.handle(.keyDown(.escape, [], isRepeat: false))
        #expect(effects == [.redraw, .status(.none), .requestCandidates(CGPoint(x: 350, y: 520), windowsOnly: false)])
        #expect(machine.hint == .hovering)
    }

    @Test func escapeWithSectionsNeedsASecondPress() {
        var machine = selectedMachine(stitched: StitchInfo(sections: 3, heightPixels: 900))
        #expect(machine.hint == .selectedStitched)
        let result22 = machine.handle(.keyDown(.escape, [], isRepeat: false))
        #expect(result22 == [.status(.escArmed(sections: 3))])
        #expect(selection(machine)?.escArmed == true)
        // Another key disarms and is handled normally.
        let nudge = machine.handle(.keyDown(.right, .command, isRepeat: false))
        #expect(nudge == [.status(.sections(StitchInfo(sections: 3, heightPixels: 900))), .redraw])
        #expect(selection(machine)?.escArmed == false)
        _ = machine.handle(.keyDown(.escape, [], isRepeat: false))
        let discarded = machine.handle(.keyDown(.escape, [], isRepeat: false))
        #expect(discarded.first == .redraw)
        #expect(machine.hint == .hovering)
    }

    @Test func deleteUndoesOnlyWithSections() {
        var plain = selectedMachine()
        let result23 = plain.handle(.keyDown(.delete, [], isRepeat: false))
        #expect(result23.isEmpty)
        var stitched = selectedMachine(stitched: StitchInfo(sections: 2, heightPixels: 700))
        let result24 = stitched.handle(.keyDown(.delete, [], isRepeat: false))
        #expect(result24 == [.undoSlice])
        let effects = stitched.handle(.sliceRemoved(StitchInfo(sections: 1, heightPixels: 400)))
        #expect(effects == [.redraw, .status(.sections(StitchInfo(sections: 1, heightPixels: 400)))])
        let gone = stitched.handle(.sliceRemoved(nil))
        #expect(gone == [.redraw, .status(.none)])
        #expect(stitched.hint == .selected)
    }

    // MARK: Extending

    @Test func arrowWhileHoveringAdoptsTheCandidateAndStarts() {
        var machine = hoveringMachine()
        let effects = machine.handle(.keyDown(.down, [], isRepeat: false))
        #expect(effects == [.redraw, .status(.extending), .beginStep(.down)])
        guard case let .extending(ext) = machine.state else { return #expect(Bool(false)) }
        #expect(ext.selection.rect == elementRect)
        #expect(ext.keyHeld && !ext.auto)
        #expect(machine.hint == .extending)
    }

    @Test func arrowWithoutCandidateBeeps() {
        var machine = ScreenshotSelectionMachine(screens: [screen])
        _ = machine.start()
        _ = machine.handle(.candidatesChanged([screenRung]))
        let result25 = machine.handle(.keyDown(.down, [], isRepeat: false))
        #expect(result25 == [.beep])
    }

    @Test func heldKeyStepsAgainOnlyWhenARepeatArrived() {
        var machine = selectedMachine()
        _ = machine.handle(.keyDown(.down, [], isRepeat: false))
        // No repeat during the step: it ends after this step.
        let info = StitchInfo(sections: 1, heightPixels: 300)
        let once = machine.handle(.stepFinished(.appended(rows: 100, info: info)))
        #expect(once == [.redraw, .status(.sections(info)), .announce(.sections(1))])
        #expect(selection(machine)?.stitched == info)

        _ = machine.handle(.keyDown(.down, [], isRepeat: false))
        let result26 = machine.handle(.keyDown(.down, [], isRepeat: true))
        #expect(result26.isEmpty)
        let twice = machine.handle(.stepFinished(.appended(rows: 100, info: StitchInfo(sections: 2, heightPixels: 500))))
        #expect(twice.last == .beginStep(.down))
        _ = machine.handle(.keyUp(.down))
        let third = machine.handle(.stepFinished(.appended(rows: 100, info: StitchInfo(sections: 3, heightPixels: 700))))
        #expect(third.last != .beginStep(.down))
        #expect(machine.hint == .selectedStitched)
    }

    @Test func optionArrowRunsUntilTheEnd() {
        var machine = selectedMachine()
        _ = machine.handle(.keyDown(.down, .option, isRepeat: false))
        _ = machine.handle(.keyUp(.down))
        let first = machine.handle(.stepFinished(.appended(rows: 100, info: StitchInfo(sections: 1, heightPixels: 300))))
        #expect(first.last == .beginStep(.down))
        let retry = machine.handle(.stepFinished(.stalled(final: false)))
        #expect(retry == [.redraw, .status(.noOverlapRetry), .beginStep(.down)])
        let end = machine.handle(.stepFinished(.endReached))
        #expect(end == [.redraw, .status(.endReached)])
        #expect(machine.hint == .selectedStitched)
    }

    @Test func escapeDuringAStepStopsAfterItAndKeepsTheSections() {
        var machine = selectedMachine()
        _ = machine.handle(.keyDown(.down, .option, isRepeat: false))
        let result27 = machine.handle(.keyDown(.escape, [], isRepeat: false))
        #expect(result27 == [.cancelStep])
        let result28 = machine.handle(.keyDown(.escape, [], isRepeat: false))
        #expect(result28.isEmpty)
        let info = StitchInfo(sections: 1, heightPixels: 300)
        let effects = machine.handle(.stepFinished(.appended(rows: 100, info: info)))
        #expect(effects == [.redraw, .status(.sections(info)), .announce(.sections(1))])
        #expect(selection(machine)?.stitched == info)
        #expect(selection(machine)?.escArmed == false)
    }

    @Test func outcomesEndExtendingWithAStatus() {
        for (outcome, status) in [
            (StepOutcome.noMovement(first: true), ScreenshotStatus.noScroll),
            (.stalled(final: true), .noOverlapStop),
            (.capReached, .capReached),
            (.endReached, .endReached),
        ] {
            var machine = selectedMachine()
            _ = machine.handle(.keyDown(.down, [], isRepeat: false))
            let result29 = machine.handle(.stepFinished(outcome))
            #expect(result29 == [.redraw, .status(status)])
            #expect(machine.hint == .selected)
        }
    }

    @Test func cancellingDuringAStepCancelsTheStepToo() {
        var machine = selectedMachine()
        _ = machine.handle(.keyDown(.down, [], isRepeat: false))
        let result30 = machine.handle(.externalCancel)
        #expect(result30 == [.cancelStep, .dismiss])
        #expect(machine.state == .idle)
    }

    @Test func wrongArrowDuringAStepStopsIt() {
        var machine = selectedMachine()
        _ = machine.handle(.keyDown(.down, .option, isRepeat: false))
        let result31 = machine.handle(.keyDown(.up, [], isRepeat: false))
        #expect(result31 == [.cancelStep])
        let effects = machine.handle(.stepFinished(.appended(rows: 50, info: StitchInfo(sections: 1, heightPixels: 250))))
        #expect(effects.last != .beginStep(.down))
        #expect(machine.hint == .selectedStitched)
    }
}

struct SnapCandidateChainTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let window = WindowInfo(id: 3, frame: CGRect(x: 100, y: 100, width: 800, height: 600), ownerPID: 1)

    @Test func rungsAreOrderedInnerToOuterWithTheScreenLast() {
        let chain = SnapCandidateChain.make(
            element: CGRect(x: 300, y: 300, width: 100, height: 30),
            block: CGRect(x: 290, y: 280, width: 120, height: 90),
            panel: CGRect(x: 200, y: 200, width: 400, height: 300),
            window: window,
            screen: screen,
            windowsOnly: false
        )
        #expect(chain.map(\.kind) == [.element, .block, .panel, .window(id: 3), .screen])
    }

    @Test func tooSmallRungsAreDropped() {
        let chain = SnapCandidateChain.make(
            element: CGRect(x: 300, y: 300, width: 20, height: 10),
            block: nil,
            panel: CGRect(x: 200, y: 200, width: 50, height: 30),
            window: window,
            screen: screen,
            windowsOnly: false
        )
        #expect(chain.map(\.kind) == [.window(id: 3), .screen])
    }

    @Test func aRungAsLargeAsTheWindowIsTheWindow() {
        let chain = SnapCandidateChain.make(
            element: nil,
            block: nil,
            panel: CGRect(x: 102, y: 102, width: 796, height: 596),
            window: window,
            screen: screen,
            windowsOnly: false
        )
        #expect(chain.map(\.kind) == [.window(id: 3), .screen])
    }

    @Test func nearDuplicatesMergeAndRectsAreClampedToTheWindow() {
        let chain = SnapCandidateChain.make(
            element: CGRect(x: 300, y: 300, width: 100, height: 30),
            block: CGRect(x: 301, y: 299, width: 100, height: 31),
            panel: CGRect(x: 0, y: 0, width: 500, height: 500),
            window: window,
            screen: screen,
            windowsOnly: false
        )
        #expect(chain.map(\.kind) == [.element, .panel, .window(id: 3), .screen])
        #expect(chain[1].rect == CGRect(x: 100, y: 100, width: 400, height: 400))
    }

    @Test func windowsOnlyKeepsWindowAndScreen() {
        let chain = SnapCandidateChain.make(
            element: CGRect(x: 300, y: 300, width: 100, height: 30),
            block: nil,
            panel: CGRect(x: 200, y: 200, width: 400, height: 300),
            window: window,
            screen: screen,
            windowsOnly: true
        )
        #expect(chain.map(\.kind) == [.window(id: 3), .screen])
        let desktop = SnapCandidateChain.make(element: nil, block: nil, panel: nil, window: nil, screen: screen, windowsOnly: true)
        #expect(desktop.map(\.kind) == [.screen])
    }

    @Test func cyclingWrapsBothWays() {
        #expect(SnapCandidateChain.cycled(0, by: 1, count: 3) == 1)
        #expect(SnapCandidateChain.cycled(2, by: 1, count: 3) == 0)
        #expect(SnapCandidateChain.cycled(0, by: -1, count: 3) == 2)
        #expect(SnapCandidateChain.cycled(0, by: 1, count: 0) == 0)
    }
}

struct SelectionGeometryTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func handlesSitOnTheCorners() {
        let result32 = ScreenshotGeometry.handle(at: CGPoint(x: 103, y: 197), in: rect)
        #expect(result32 == .topLeft)
        let result33 = ScreenshotGeometry.handle(at: CGPoint(x: 300, y: 200), in: rect)
        #expect(result33 == .topRight)
        let result34 = ScreenshotGeometry.handle(at: CGPoint(x: 96, y: 104), in: rect)
        #expect(result34 == .bottomLeft)
        let result35 = ScreenshotGeometry.handle(at: CGPoint(x: 305, y: 95), in: rect)
        #expect(result35 == .bottomRight)
        let result36 = ScreenshotGeometry.handle(at: CGPoint(x: 200, y: 150), in: rect)
        #expect(result36 == nil)
        let result37 = ScreenshotGeometry.handle(at: CGPoint(x: 110, y: 190), in: rect)
        #expect(result37 == nil)
    }

    @Test func resizingKeepsTheOppositeCorner() {
        #expect(ScreenshotGeometry.resized(rect, handle: .topRight, to: CGPoint(x: 350, y: 250), within: bounds) == CGRect(x: 100, y: 100, width: 250, height: 150))
        #expect(ScreenshotGeometry.resized(rect, handle: .bottomLeft, to: CGPoint(x: 50, y: 50), within: bounds) == CGRect(x: 50, y: 50, width: 250, height: 150))
        // Dragging past the opposite corner flips the rect; past the screen edge clamps it.
        #expect(ScreenshotGeometry.resized(rect, handle: .topRight, to: CGPoint(x: 50, y: 50), within: bounds) == CGRect(x: 50, y: 50, width: 50, height: 50))
        #expect(ScreenshotGeometry.resized(rect, handle: .topRight, to: CGPoint(x: 1200, y: 900), within: bounds) == CGRect(x: 100, y: 100, width: 900, height: 700))
    }

    @Test func nudgingStopsAtTheEdges() {
        #expect(ScreenshotGeometry.nudged(rect, key: .right, step: 10, within: bounds) == CGRect(x: 110, y: 100, width: 200, height: 100))
        #expect(ScreenshotGeometry.nudged(rect, key: .down, step: 150, within: bounds) == CGRect(x: 100, y: 0, width: 200, height: 100))
        #expect(ScreenshotGeometry.nudged(rect, key: .confirm, step: 10, within: bounds) == rect)
    }

    @Test func theScreenContainingAPointOrTheNearestOne() {
        let left = CGRect(x: 0, y: 0, width: 100, height: 100)
        let right = CGRect(x: 100, y: 0, width: 100, height: 100)
        #expect(ScreenshotGeometry.screen(containing: CGPoint(x: 150, y: 50), in: [left, right]) == right)
        #expect(ScreenshotGeometry.screen(containing: CGPoint(x: -20, y: 50), in: [left, right]) == left)
        #expect(ScreenshotGeometry.screen(containing: CGPoint(x: 250, y: 50), in: [left, right]) == right)
        #expect(ScreenshotGeometry.screen(containing: .zero, in: []) == nil)
    }

    @Test func deleteKeyIsMapped() {
        #expect(ScreenshotKeyMap.key(forKeyCode: 51) == .delete)
        #expect(ScreenshotKey.down.isArrow && !ScreenshotKey.space.isArrow)
    }
}

struct ScrollSessionTests {
    private func frame(_ height: Int, offset: Int) -> PixelBuffer {
        var buffer = PixelBuffer(width: 64, height: height)
        for row in 0..<height {
            let index = offset + row
            if index % 10 >= 7 { buffer.fill(PixelRect(x: 0, y: row, width: 64, height: 1), b: 255, g: 255, r: 255) } else {
                buffer.fill(PixelRect(x: 0, y: row, width: 64, height: 1), b: UInt8(index & 0xFF), g: UInt8((index >> 8) & 0xFF), r: 9)
            }
        }
        return buffer
    }

    @Test func stepsReportProgressAndTheEnd() {
        var session = ScrollSession(firstFrame: frame(400, offset: 0), scale: 2)
        let first = session.accept(frame(400, offset: 250), direction: .down)
        #expect(first == .appended(rows: 250, info: StitchInfo(sections: 1, heightPixels: 650)))
        let still = session.accept(frame(400, offset: 250), direction: .down)
        #expect(still == .noMovement(first: false))
        let end = session.accept(frame(400, offset: 250), direction: .down)
        #expect(end == .endReached)
        #expect(session.info == StitchInfo(sections: 1, heightPixels: 650))
        #expect(session.composite().height == 650)
    }

    @Test func noMovementOnTheFirstStepMeansNoScrolling() {
        var session = ScrollSession(firstFrame: frame(400, offset: 0), scale: 2)
        let result38 = session.accept(frame(400, offset: 0), direction: .down)
        #expect(result38 == .noMovement(first: true))
    }

    @Test func stallsBecomeFinalTheSecondTime() {
        var session = ScrollSession(firstFrame: frame(400, offset: 0), scale: 2)
        let result39 = session.accept(frame(400, offset: 900), direction: .down)
        #expect(result39 == .stalled(final: false))
        let result40 = session.accept(frame(400, offset: 900), direction: .down)
        #expect(result40 == .stalled(final: true))
        _ = session.accept(frame(400, offset: 250), direction: .down)
        let result41 = session.accept(frame(400, offset: 50), direction: .up)
        #expect(result41 == .stalled(final: true))
    }

    @Test func undoRestoresTheCounters() {
        var session = ScrollSession(firstFrame: frame(400, offset: 0), scale: 2)
        _ = session.accept(frame(400, offset: 250), direction: .down)
        _ = session.accept(frame(400, offset: 900), direction: .down)
        let result42 = session.undo()
        #expect(result42)
        #expect(session.steps == 0)
        #expect(session.consecutiveStalls == 0)
        #expect(session.info.sections == 0)
        let result43 = session.undo()
        #expect(!result43)
    }

    @Test func plannerSizesAndChunks() {
        #expect(ScrollPlanner.stepPoints(selectionHeight: 100) == 200)
        #expect(ScrollPlanner.stepPoints(selectionHeight: 500) == 300)
        #expect(ScrollPlanner.stepPoints(selectionHeight: 10_000) == 1_600)
        #expect(ScrollPlanner.chunks(deltaPoints: 300, direction: .down, reversed: false) == [-160, -140])
        #expect(ScrollPlanner.chunks(deltaPoints: 300, direction: .up, reversed: false) == [160, 140])
        #expect(ScrollPlanner.chunks(deltaPoints: 300, direction: .down, reversed: true) == [160, 140])
        #expect(ScrollPlanner.chunks(deltaPoints: 0, direction: .down, reversed: false).isEmpty)
    }
}
