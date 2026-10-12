import Testing
@testable import CopyPalCore

private let cmdV = KeyStroke(isPasteKey: true, modifiers: .command)
private let cmdVRepeat = KeyStroke(isPasteKey: true, modifiers: .command, isRepeat: true)
private let vUp = KeyStroke(isPasteKey: true, modifiers: .command)
private let vUpWithoutCommand = KeyStroke(isPasteKey: true, modifiers: [])
private let otherKey = KeyStroke(isPasteKey: false, modifiers: .command)

struct HoldGestureStateMachineTests {
    /// Runs inputs and returns the machine plus every output.
    private func run(_ inputs: [HoldGestureInput], enabled: Bool = true) -> (HoldGestureStateMachine, [HoldGestureOutput]) {
        var machine = HoldGestureStateMachine()
        machine.isEnabled = enabled
        let outputs = inputs.map { machine.handle($0) }
        return (machine, outputs)
    }

    // MARK: Tap → normal paste

    @Test func cmdVDownIsSwallowedAndStartsTimer() {
        let (machine, outputs) = run([.keyDown(cmdV)])
        #expect(outputs == [HoldGestureOutput(.swallow, [.startTimer(generation: 1)])])
        #expect(machine.state == .waiting(generation: 1))
    }

    @Test func quickTapPastesOnRelease() {
        let (machine, outputs) = run([.keyDown(cmdV), .keyUp(vUp)])
        #expect(outputs[1] == HoldGestureOutput(.swallow, [.cancelTimer, .synthesizePaste]))
        #expect(machine.state == .idle)
    }

    @Test func releasingCommandFirstStillPastes() {
        let (machine, outputs) = run([.keyDown(cmdV), .flagsChanged, .keyUp(vUpWithoutCommand)])
        #expect(outputs[1] == .pass)
        #expect(outputs[2] == HoldGestureOutput(.swallow, [.cancelTimer, .synthesizePaste]))
        #expect(machine.state == .idle)
    }

    @Test func keyRepeatWhileWaitingIsSwallowed() {
        let (machine, outputs) = run([.keyDown(cmdV), .keyDown(cmdVRepeat), .keyDown(cmdVRepeat)])
        #expect(outputs[1] == .swallow)
        #expect(outputs[2] == .swallow)
        #expect(machine.state == .waiting(generation: 1))
    }

    @Test func otherKeyWhileWaitingPastesThenReplaysThatKey() {
        let (machine, outputs) = run([.keyDown(cmdV), .keyDown(otherKey)])
        #expect(outputs[1] == HoldGestureOutput(.swallow, [.cancelTimer, .synthesizePaste, .replayCurrentEvent]))
        #expect(machine.state == .idle)
    }

    @Test func otherKeyUpWhileWaitingPasses() {
        let (machine, outputs) = run([.keyDown(cmdV), .keyUp(otherKey)])
        #expect(outputs[1] == .pass)
        #expect(machine.state == .waiting(generation: 1))
    }

    // MARK: Hold → popup

    @Test func thresholdOpensPopup() {
        let (machine, outputs) = run([.keyDown(cmdV), .thresholdElapsed(generation: 1)])
        #expect(outputs[1] == HoldGestureOutput(.pass, [.showPopup]))
        #expect(machine.state == .holding)
    }

    @Test func heldKeyNeverReachesTargetWhilePopupIsOpen() {
        let (machine, outputs) = run([
            .keyDown(cmdV), .thresholdElapsed(generation: 1),
            .keyDown(cmdVRepeat), .keyDown(cmdVRepeat), .keyUp(vUp),
        ])
        #expect(Array(outputs[2...]) == [.swallow, .swallow, .swallow])
        #expect(machine.state == .holding)
    }

    @Test func noPasteWhenHoldEnds() {
        let (_, outputs) = run([.keyDown(cmdV), .thresholdElapsed(generation: 1), .keyUp(vUp)])
        #expect(!outputs.flatMap(\.effects).contains(.synthesizePaste))
    }

    @Test func otherKeysPassToPopupWhileHolding() {
        let digit = KeyStroke(isPasteKey: false, modifiers: .command)
        let (_, outputs) = run([.keyDown(cmdV), .thresholdElapsed(generation: 1), .keyDown(digit), .keyUp(digit)])
        #expect(outputs[2] == .pass)
        #expect(outputs[3] == .pass)
    }

    @Test func pressingCmdVAgainWhilePopupIsOpenIsSwallowed() {
        let (_, outputs) = run([.keyDown(cmdV), .thresholdElapsed(generation: 1), .keyUp(vUp), .keyDown(cmdV)])
        #expect(outputs[3] == .swallow)
    }

    @Test func closingPopupReturnsToIdle() {
        let (machine, _) = run([.keyDown(cmdV), .thresholdElapsed(generation: 1), .popupClosed])
        #expect(machine.state == .idle)
    }

    @Test func nextCmdVAfterPopupStartsFreshGeneration() {
        let (machine, outputs) = run([
            .keyDown(cmdV), .thresholdElapsed(generation: 1), .keyUp(vUp), .popupClosed, .keyDown(cmdV),
        ])
        #expect(outputs[4] == HoldGestureOutput(.swallow, [.startTimer(generation: 2)]))
        #expect(machine.state == .waiting(generation: 2))
    }

    // MARK: Timers

    @Test func staleTimerIsIgnored() {
        let (machine, outputs) = run([
            .keyDown(cmdV), .keyUp(vUp),            // tap, generation 1 cancelled
            .keyDown(cmdV),                         // generation 2
            .thresholdElapsed(generation: 1),       // late timer from the tap
        ])
        #expect(outputs[3] == .pass)
        #expect(machine.state == .waiting(generation: 2))
    }

    @Test func timerAfterTapIsIgnored() {
        let (machine, outputs) = run([.keyDown(cmdV), .keyUp(vUp), .thresholdElapsed(generation: 1)])
        #expect(outputs[2] == .pass)
        #expect(machine.state == .idle)
    }

    // MARK: Pass-through

    @Test(arguments: [
        KeyModifiers([.command, .shift]),
        [.command, .option],
        [.command, .control],
        [],
        [.option],
    ])
    func otherChordsPassUntouched(modifiers: KeyModifiers) {
        let (machine, outputs) = run([.keyDown(KeyStroke(isPasteKey: true, modifiers: modifiers))])
        #expect(outputs == [.pass])
        #expect(machine.state == .idle)
    }

    @Test func capsLockAndFnDoNotMatter() {
        let stroke = KeyStroke(isPasteKey: true, modifiers: [.command, .capsLock, .function])
        let (_, outputs) = run([.keyDown(stroke)])
        #expect(outputs[0].disposition == .swallow)
    }

    @Test func ordinaryTypingPasses() {
        let (_, outputs) = run([.keyDown(KeyStroke(isPasteKey: false, modifiers: [])), .keyUp(KeyStroke(isPasteKey: false, modifiers: []))])
        #expect(outputs == [.pass, .pass])
    }

    @Test func repeatWithoutPriorDownPassesInIdle() {
        let (_, outputs) = run([.keyDown(cmdVRepeat)])
        #expect(outputs == [.pass])
    }

    @Test func ownSyntheticEventsAlwaysPass() {
        let own = KeyStroke(isPasteKey: true, modifiers: .command, isOwnSynthetic: true)
        let (idle, idleOutputs) = run([.keyDown(own), .keyUp(own)])
        #expect(idleOutputs == [.pass, .pass])
        #expect(idle.state == .idle)

        let (holding, holdingOutputs) = run([.keyDown(cmdV), .thresholdElapsed(generation: 1), .keyDown(own)])
        #expect(holdingOutputs[2] == .pass)
        #expect(holding.state == .holding)
    }

    @Test func disabledMachinePassesCmdV() {
        let (machine, outputs) = run([.keyDown(cmdV), .keyUp(vUp)], enabled: false)
        #expect(outputs == [.pass, .pass])
        #expect(machine.state == .idle)
    }

    @Test func flagsChangedAlwaysPasses() {
        let (_, outputs) = run([.flagsChanged, .keyDown(cmdV), .flagsChanged])
        #expect(outputs[0] == .pass)
        #expect(outputs[2] == .pass)
    }

    @Test func popupClosedInIdleIsHarmless() {
        let (machine, outputs) = run([.popupClosed])
        #expect(outputs == [.pass])
        #expect(machine.state == .idle)
    }

    // MARK: Tap reset

    @Test func tapResetWhileWaitingCancelsTimer() {
        let (machine, outputs) = run([.keyDown(cmdV), .tapReset])
        #expect(outputs[1] == HoldGestureOutput(.pass, [.cancelTimer]))
        #expect(machine.state == .idle)
    }

    @Test func tapResetWhileHoldingReturnsToIdle() {
        let (machine, outputs) = run([.keyDown(cmdV), .thresholdElapsed(generation: 1), .tapReset])
        #expect(outputs[2] == .pass)
        #expect(machine.state == .idle)
    }

    @Test func modifierSymbols() {
        #expect(KeyModifiers([.command, .shift]).symbols == "⇧⌘")
        #expect(KeyModifiers([]).symbols == "")
    }
}
