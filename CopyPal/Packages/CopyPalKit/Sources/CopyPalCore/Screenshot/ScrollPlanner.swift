import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// How much of a scrolling capture exists so far.
public struct StitchInfo: Sendable, Equatable {
    public var sections: Int
    public var heightPixels: Int

    public init(sections: Int, heightPixels: Int) {
        self.sections = sections
        self.heightPixels = heightPixels
    }
}

/// What one scroll step achieved.
public enum StepOutcome: Sendable, Equatable {
    case appended(rows: Int, info: StitchInfo)
    /// Nothing moved. `first`: already on the first step – the content does not scroll.
    case noMovement(first: Bool)
    /// Two steps in a row without movement: the end of the content.
    case endReached
    /// The frame could not be joined (ambiguous or no overlap). `final`: twice in a row.
    case stalled(final: Bool)
    /// Height, memory or step limit.
    case capReached
}

/// Sizes and timings of the scroll steps (M11). A step scrolls about 60 % of the
/// selection, so consecutive frames overlap by 40 % and the stitcher can match them.
public enum ScrollPlanner {
    public static let minimumStepPoints: CGFloat = 200
    public static let maximumStepPoints: CGFloat = 1_600
    /// Scroll wheel deltas larger than this are not honoured by every app.
    public static let maximumChunkPoints: CGFloat = 160
    public static let maximumSteps = 200
    public static let maximumHeightPixels = 20_000
    /// 4 bytes per pixel: 200 MB of frames and composite.
    public static let maximumCanvasBytes = 200_000_000

    /// Points to scroll for a selection `selectionHeight` points tall.
    public static func stepPoints(selectionHeight: CGFloat) -> CGFloat {
        min(max((selectionHeight * 0.6).rounded(.down), minimumStepPoints), maximumStepPoints)
    }

    /// `delta` points as scroll-wheel deltas of at most `maximumChunkPoints` each.
    /// Negative values scroll down (macOS convention); `reversed` flips them.
    public static func chunks(deltaPoints delta: CGFloat, direction: ScrollDirection, reversed: Bool) -> [Int32] {
        var remaining = Int(delta.rounded())
        var chunks: [Int32] = []
        let chunk = Int(maximumChunkPoints)
        while remaining > 0 {
            let part = min(remaining, chunk)
            chunks.append(Int32(part))
            remaining -= part
        }
        let down = (direction == .down) != reversed
        return down ? chunks.map { -$0 } : chunks
    }
}

/// The frames of one scrolling capture: wraps `VerticalStitcher` with the step
/// bookkeeping the overlay needs (stall and end counters, limits).
public struct ScrollSession: Sendable {
    public private(set) var stitcher: VerticalStitcher
    public private(set) var steps = 0
    public private(set) var consecutiveNoMovement = 0
    public private(set) var consecutiveStalls = 0
    public let frameBytes: Int

    public init(firstFrame: PixelBuffer, scale: Int) {
        stitcher = VerticalStitcher(
            firstFrame: firstFrame,
            scale: scale,
            settings: StitchSettings(maximumHeight: ScrollPlanner.maximumHeightPixels)
        )
        frameBytes = firstFrame.bgra.count
    }

    public var info: StitchInfo {
        StitchInfo(sections: stitcher.sectionCount, heightPixels: stitcher.height)
    }

    /// Frames kept for undo plus the composite.
    public var byteCount: Int {
        frameBytes * (stitcher.sectionCount + 1) + stitcher.height * stitcher.latestFrame.width * PixelBuffer.bytesPerPixel
    }

    public var direction: ScrollDirection? { stitcher.direction }

    public mutating func accept(_ frame: PixelBuffer, direction: ScrollDirection) -> StepOutcome {
        switch stitcher.append(frame, direction: direction) {
        case let .appended(rows):
            steps += 1
            consecutiveNoMovement = 0
            consecutiveStalls = 0
            if steps >= ScrollPlanner.maximumSteps || byteCount >= ScrollPlanner.maximumCanvasBytes {
                return .capReached
            }
            return .appended(rows: rows, info: info)
        case .unchanged:
            consecutiveNoMovement += 1
            return consecutiveNoMovement >= 2 ? .endReached : .noMovement(first: steps == 0)
        case .ambiguous, .noOverlap:
            consecutiveStalls += 1
            return .stalled(final: consecutiveStalls >= 2)
        case .reachedLimit:
            return .capReached
        case .wrongDirection:
            return .stalled(final: true)
        }
    }

    /// Drops the newest section; the counters start over.
    @discardableResult
    public mutating func undo() -> Bool {
        guard stitcher.undo() else { return false }
        steps = max(steps - 1, 0)
        consecutiveNoMovement = 0
        consecutiveStalls = 0
        return true
    }

    public func composite() -> PixelBuffer {
        stitcher.composite()
    }
}
