#if os(macOS)
import CoreGraphics
import Foundation
import CopyPalCore

/// Intercepts ⌘V system-wide with an active event tap and runs the hold gesture.
///
/// Threading: the tap, its timer and `HoldGestureStateMachine` live on one dedicated
/// thread with its own run loop, so a busy main thread never delays typing. The
/// callback does no I/O and no allocation-heavy work. UI work (`onShowPopup`) is
/// dispatched to the main thread. Settings are read through a lock.
public final class EventTapController: @unchecked Sendable {
    /// Called on the main thread when the user holds ⌘V past the threshold.
    public var onShowPopup: (@MainActor @Sendable () -> Void)? {
        get { lock.withLock { showPopupHandler } }
        set { lock.withLock { showPopupHandler = newValue } }
    }

    public let diagnostics = InputDiagnostics()

    /// Seconds ⌘V must be held before the popup opens.
    public var holdThreshold: TimeInterval {
        get { lock.withLock { threshold } }
        set { lock.withLock { threshold = newValue } }
    }

    /// Key code that produces "v" with ⌘ in the current layout.
    public var pasteKeyCode: UInt16 {
        get { lock.withLock { keyCode } }
        set { lock.withLock { keyCode = newValue } }
    }

    /// False while the frontmost app is on the "hold off" list: ⌘V then passes untouched.
    public var holdEnabled: Bool {
        get { lock.withLock { holdAllowed } }
        set { lock.withLock { holdAllowed = newValue } }
    }

    public var isRunning: Bool {
        lock.withLock { tap != nil }
    }

    /// False while macOS has the tap disabled (e.g. after a timeout, before it is re-enabled).
    public var isEnabled: Bool {
        guard let tap = lock.withLock({ self.tap }) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    // Shared, guarded by `lock`.
    private let lock = NSLock()
    private var showPopupHandler: (@MainActor @Sendable () -> Void)?
    private var threshold: TimeInterval
    private var keyCode: UInt16
    private var holdAllowed = true
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    // Confined to the tap thread.
    private var machine = HoldGestureStateMachine()
    private var holdTimer: CFRunLoopTimer?
    private var pasteKeyDownAt: UInt64 = 0

    public init(holdThreshold: TimeInterval, pasteKeyCode: UInt16) {
        threshold = holdThreshold
        keyCode = pasteKeyCode
    }

    // MARK: Lifecycle (main thread)

    /// Creates the tap on its own thread. Returns false when macOS refuses it, which
    /// almost always means the Accessibility permission is missing.
    @discardableResult
    public func start() -> Bool {
        if isRunning { return true }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        lock.withLock { tap = port }
        let thread = Thread { [self] in
            self.runTapLoop()
        }
        thread.name = "CopyPal.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        diagnostics.log(kind: "Tap", decision: "gestartet")
        return true
    }

    /// Removes the tap immediately (e.g. when the permission is revoked, so the
    /// keyboard never depends on a tap macOS no longer services).
    public func stop() {
        let (port, loop) = lock.withLock { () -> (CFMachPort?, CFRunLoop?) in
            defer {
                tap = nil
                runLoop = nil
            }
            return (tap, runLoop)
        }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let loop {
            CFRunLoopStop(loop)
        }
        diagnostics.log(kind: "Tap", decision: "gestoppt")
    }

    /// Re-enables a tap macOS disabled. Safe to call periodically.
    public func ensureEnabled() {
        guard let port = lock.withLock({ tap }), !CGEvent.tapIsEnabled(tap: port) else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        perform { $0.apply(input: .tapReset, event: nil) }
        diagnostics.log(kind: "Tap", decision: "wieder eingeschaltet (Wächter)")
    }

    /// Tell the gesture that the popup is gone (main thread).
    public func popupDidClose() {
        perform { $0.apply(input: .popupClosed, event: nil) }
    }

    // MARK: Tap thread

    private func runTapLoop() {
        guard let port = lock.withLock({ tap }),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            return
        }
        let loop = CFRunLoopGetCurrent()
        lock.withLock { runLoop = loop }
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        CFRunLoopRun()
    }

    /// Runs `work` on the tap thread.
    private func perform(_ work: @escaping @Sendable (EventTapController) -> Void) {
        guard let loop = lock.withLock({ runLoop }) else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [self] in
            work(self)
        }
        CFRunLoopWakeUp(loop)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = lock.withLock({ tap }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            apply(input: .tapReset, event: nil)
            diagnostics.log(kind: "Tap", decision: type == .tapDisabledByTimeout ? "Timeout – wieder eingeschaltet" : "vom System pausiert")
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        let started = DispatchTime.now().uptimeNanoseconds
        let eventKeyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let stroke = KeyStroke(
            isPasteKey: eventKeyCode == pasteKeyCode,
            modifiers: KeyModifiers(event.flags),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            isOwnSynthetic: PasteSynthesizer.isOwn(event)
        )
        let input: HoldGestureInput = switch type {
        case .keyDown: .keyDown(stroke)
        case .keyUp: .keyUp(stroke)
        default: .flagsChanged
        }

        if type == .keyDown {
            machine.isEnabled = holdEnabled
        }
        let disposition = apply(input: input, event: event)

        if type != .flagsChanged, stroke.isPasteKey || stroke.modifiers.contains(.command) {
            diagnostics.log(
                kind: type == .keyDown ? "↓" : "↑",
                keyCode: eventKeyCode,
                modifiers: stroke.modifiers,
                isRepeat: stroke.isRepeat,
                sourceState: event.getIntegerValueField(.eventSourceStateID),
                sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
                decision: stroke.isOwnSynthetic ? "eigenes Event" : (disposition == .swallow ? "geschluckt" : "durchgelassen")
            )
        }
        diagnostics.recordCallback(milliseconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)

        return disposition == .swallow ? nil : Unmanaged.passUnretained(event)
    }

    @discardableResult
    private func apply(input: HoldGestureInput, event: CGEvent?) -> HoldGestureDisposition {
        let output = machine.handle(input)
        for effect in output.effects {
            switch effect {
            case let .startTimer(generation):
                pasteKeyDownAt = DispatchTime.now().uptimeNanoseconds
                startHoldTimer(generation: generation)
            case .cancelTimer:
                cancelHoldTimer()
            case .synthesizePaste:
                let held = Double(DispatchTime.now().uptimeNanoseconds - pasteKeyDownAt) / 1_000_000
                diagnostics.recordTap(milliseconds: held)
                PasteSynthesizer.postPaste(keyCode: pasteKeyCode)
            case .replayCurrentEvent:
                if let event {
                    PasteSynthesizer.replay(event)
                }
            case .showPopup:
                diagnostics.markPopupRequested()
                diagnostics.log(kind: "Pop-up", decision: "angefordert")
                if let handler = onShowPopup {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            handler()
                        }
                    }
                }
            }
        }
        return output.disposition
    }

    private func startHoldTimer(generation: Int) {
        cancelHoldTimer()
        guard let loop = lock.withLock({ runLoop }) else { return }
        let fireDate = CFAbsoluteTimeGetCurrent() + holdThreshold
        let timer = CFRunLoopTimerCreateWithHandler(nil, fireDate, 0, 0, 0) { [self] _ in
            self.holdTimer = nil
            self.apply(input: .thresholdElapsed(generation: generation), event: nil)
        }
        holdTimer = timer
        CFRunLoopAddTimer(loop, timer, .commonModes)
    }

    private func cancelHoldTimer() {
        if let holdTimer {
            CFRunLoopTimerInvalidate(holdTimer)
        }
        holdTimer = nil
    }
}
#endif
