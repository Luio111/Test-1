#if os(macOS)
import CoreGraphics
import CopyPalCore

/// Posts scroll-wheel events for the scrolling capture (M11) and parks the cursor over
/// the selection meanwhile. The events carry CopyPal's marker like the paste events.
public enum ScrollSynthesizer {
    public enum Units: Sendable, Equatable {
        /// Continuous ("trackpad") scrolling; what apps honour most reliably.
        case pixel
        /// Whole lines, the mouse-wheel kind; the retry when pixels moved nothing.
        case line
    }

    /// A scroll event of `delta` (negative scrolls down) at `location` (top-left
    /// coordinates, like `CGEvent.location`).
    public static func makeEvent(delta: Int32, units: Units, at location: CGPoint, source: CGEventSource? = nil) -> CGEvent? {
        let cgUnits: CGScrollEventUnit = units == .pixel ? .pixel : .line
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: cgUnits, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else {
            return nil
        }
        event.location = location
        if units == .pixel {
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        }
        event.setIntegerValueField(.eventSourceUserData, value: PasteSynthesizer.marker)
        return event
    }

    /// Posts `chunks` one after another with `gap` between them: deltas that arrive in
    /// one burst are dropped by some apps.
    public static func post(chunks: [Int32], at location: CGPoint, gap: Duration = .milliseconds(8)) async {
        for (index, chunk) in chunks.enumerated() {
            let source = CGEventSource(stateID: .privateState)
            makeEvent(delta: chunk, units: .pixel, at: location, source: source)?.post(tap: .cghidEventTap)
            if index < chunks.count - 1 {
                try? await Task.sleep(for: gap)
            }
        }
    }

    /// One line-based event, the retry for content that ignores pixel deltas.
    public static func postLines(_ lines: Int32, at location: CGPoint) {
        let source = CGEventSource(stateID: .privateState)
        makeEvent(delta: lines, units: .line, at: location, source: source)?.post(tap: .cghidEventTap)
    }

    /// Moves the cursor to `point` (top-left coordinates) and returns where it was, for
    /// `restoreCursor`. Scroll events reach the window under the cursor, so it sits
    /// over the selection while a step runs.
    public static func warpCursor(to point: CGPoint) -> CGPoint {
        let previous = CGEvent(source: nil)?.location ?? point
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
        return previous
    }

    public static func restoreCursor(_ point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
#endif
