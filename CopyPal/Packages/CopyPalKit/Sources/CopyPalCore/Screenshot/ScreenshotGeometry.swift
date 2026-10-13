import Foundation

/// A rectangle in whole device pixels of one display, origin at the display's top-left
/// corner: what ScreenCaptureKit returns and what the stitcher works on.
public struct PixelRect: Sendable, Hashable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

/// Conversions between the coordinate systems a screenshot touches (ROADMAP M11):
/// - **AppKit**: points, origin at the bottom left of the primary display, y up
///   (`NSScreen.frame`, `NSEvent.mouseLocation`, the overlay's own geometry).
/// - **Top-left**: points, origin at the top left of the primary display, y down
///   (`kCGWindowBounds`, `CGEvent.location`).
/// - **Display-local**: top-left points relative to one display
///   (`SCStreamConfiguration.sourceRect`).
/// - **Pixels**: display-local, multiplied by the backing scale (`PixelRect`).
public enum ScreenshotGeometry {
    /// Guards against floating-point noise such as 100.00000001 × 2 rounding up to 201.
    private static let epsilon: CGFloat = 1e-6

    // MARK: AppKit ↔ top-left

    /// An AppKit rect as a top-left rect (and back: the formula is its own inverse).
    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        let rect = rect.standardized
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// An AppKit point as a top-left point (and back).
    public static func flipped(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    // MARK: Display-local points and pixels

    /// `rect` (AppKit) relative to the top-left corner of `displayFrame` (AppKit).
    public static func displayLocal(_ rect: CGRect, in displayFrame: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX - displayFrame.minX,
            y: displayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// The whole device pixels covering a display-local rect: near edges rounded down,
    /// far edges rounded up, so no border pixel is ever lost.
    public static func pixels(_ local: CGRect, scale: CGFloat) -> PixelRect {
        let local = local.standardized
        let minX = Int((local.minX * scale + epsilon).rounded(.down))
        let minY = Int((local.minY * scale + epsilon).rounded(.down))
        let maxX = Int((local.maxX * scale - epsilon).rounded(.up))
        let maxY = Int((local.maxY * scale - epsilon).rounded(.up))
        return PixelRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }

    /// The display-local points of a pixel rect. Derived from whole pixels, so a capture
    /// configured with this rect and `pixels.width × pixels.height` never disagrees by one pixel.
    public static func points(_ pixels: PixelRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: CGFloat(pixels.x) / scale,
            y: CGFloat(pixels.y) / scale,
            width: CGFloat(pixels.width) / scale,
            height: CGFloat(pixels.height) / scale
        )
    }

    /// A display-local rect back in AppKit coordinates.
    public static func appKit(fromDisplayLocal local: CGRect, in displayFrame: CGRect) -> CGRect {
        CGRect(
            x: displayFrame.minX + local.minX,
            y: displayFrame.maxY - local.maxY,
            width: local.width,
            height: local.height
        )
    }

    // MARK: Selection rectangles

    /// `rect` limited to `bounds`; `.zero` when they do not overlap.
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let intersection = rect.standardized.intersection(bounds)
        return intersection.isNull || intersection.isEmpty ? .zero : intersection
    }

    /// The rectangle of a drag from `anchor` to `current`, standardized. With `square`
    /// (⇧) the shorter side grows to the longer one, towards the pointer; with
    /// `fromCenter` (⌥) the anchor is the center and the rect grows in all directions.
    public static func dragRect(anchor: CGPoint, current: CGPoint, square: Bool = false, fromCenter: Bool = false) -> CGRect {
        var dx = current.x - anchor.x
        var dy = current.y - anchor.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if fromCenter {
            return CGRect(x: anchor.x - dx, y: anchor.y - dy, width: 2 * dx, height: 2 * dy).standardized
        }
        return CGRect(x: anchor.x, y: anchor.y, width: dx, height: dy).standardized
    }

    /// `rect` moved by (`dx`, `dy`) but kept inside `bounds` (pushed back at the edges).
    public static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGRect {
        var moved = rect.standardized.offsetBy(dx: dx, dy: dy)
        if moved.minX < bounds.minX { moved.origin.x = bounds.minX }
        if moved.maxX > bounds.maxX { moved.origin.x = bounds.maxX - moved.width }
        if moved.minY < bounds.minY { moved.origin.y = bounds.minY }
        if moved.maxY > bounds.maxY { moved.origin.y = bounds.maxY - moved.height }
        return moved
    }
}
