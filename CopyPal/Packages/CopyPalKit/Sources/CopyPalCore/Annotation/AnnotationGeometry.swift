import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The measuring behind the markup editor: drawing with ⇧, hit testing, the arrow's
/// head, the text's box. Points of the picture, origin top left, y down.
public enum AnnotationGeometry {
    /// Measures a text (lines split at "\n") in the system font; supplied by the
    /// renderer, which knows the font.
    public typealias TextMeasure = (_ text: String, _ fontSize: Double) -> CGSize

    // MARK: Drawing

    /// The rectangle spanned by two corners. `square`: a square (⇧) towards the pointer,
    /// `fromCenter`: `start` is the centre (⌥).
    public static func rect(from start: CGPoint, to end: CGPoint, square: Bool = false, fromCenter: Bool = false) -> CGRect {
        var dx = end.x - start.x
        var dy = end.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if fromCenter {
            return CGRect(x: start.x - abs(dx), y: start.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        }
        return CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
    }

    /// `end` moved onto the nearest multiple of 45° around `start` (⇧ while drawing a line).
    public static func snapped(_ end: CGPoint, from start: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return end }
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: start.x + length * cos(angle), y: start.y + length * sin(angle))
    }

    /// Fewer points for a freehand stroke (Ramer–Douglas–Peucker): the mouse reports
    /// a point every few pixels, the shape needs far fewer.
    public static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var ranges = [(0, points.count - 1)]
        while let (first, last) = ranges.popLast() {
            guard last > first + 1 else { continue }
            var farthest = first
            var farthestDistance: CGFloat = 0
            for index in (first + 1)..<last {
                let distance = distance(from: points[index], toSegment: points[first], points[last])
                if distance > farthestDistance {
                    farthestDistance = distance
                    farthest = index
                }
            }
            if farthestDistance > tolerance {
                keep[farthest] = true
                ranges.append((first, farthest))
                ranges.append((farthest, last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    // MARK: Arrow

    public struct ArrowHead: Sendable, Equatable {
        public var tip: CGPoint
        public var left: CGPoint
        public var right: CGPoint
        /// Where the shaft ends, inside the head, so the thick line never pokes out of the tip.
        public var base: CGPoint
    }

    /// The filled head of an arrow from `start` to `end`: grows with the line, at most
    /// 60 % of the arrow's length.
    public static func arrowHead(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> ArrowHead {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else {
            return ArrowHead(tip: end, left: end, right: end, base: end)
        }
        let headLength = min(max(lineWidth * 3.2 + 8, 12), length * 0.6)
        let halfWidth = headLength * 0.58
        let ux = dx / length
        let uy = dy / length
        let back = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let left = CGPoint(x: back.x + uy * halfWidth, y: back.y - ux * halfWidth)
        let right = CGPoint(x: back.x - uy * halfWidth, y: back.y + ux * halfWidth)
        let base = CGPoint(x: end.x - ux * headLength * 0.7, y: end.y - uy * headLength * 0.7)
        return ArrowHead(tip: end, left: left, right: right, base: base)
    }

    // MARK: Text

    /// Space between a text and the edge of its bubble.
    public static func textPadding(fontSize: Double) -> CGSize {
        CGSize(width: (fontSize * 0.5).rounded(), height: (fontSize * 0.28).rounded())
    }

    /// The box of a text: its lines plus the bubble's padding (kept without a bubble
    /// too, so switching the bubble does not move the words).
    public static func textFrame(_ text: String, at origin: CGPoint, fontSize: Double, measure: TextMeasure) -> CGRect {
        let size = measure(text.isEmpty ? " " : text, fontSize)
        let padding = textPadding(fontSize: fontSize)
        return CGRect(x: origin.x, y: origin.y, width: size.width + padding.width * 2, height: size.height + padding.height * 2)
    }

    // MARK: Bounds and hits

    /// Everything the annotation paints, line width included.
    public static func bounds(of annotation: Annotation, measure: TextMeasure) -> CGRect {
        let half = CGFloat(annotation.style.lineWidth) / 2
        switch annotation.shape {
        case let .pen(points), let .highlighter(points):
            return boundingRect(points).insetBy(dx: -half, dy: -half)
        case let .line(start, end):
            return boundingRect([start, end]).insetBy(dx: -half, dy: -half)
        case let .arrow(start, end):
            let head = arrowHead(from: start, to: end, lineWidth: CGFloat(annotation.style.lineWidth))
            return boundingRect([start, end, head.left, head.right]).insetBy(dx: -half, dy: -half)
        case let .rectangle(rect), let .ellipse(rect):
            return annotation.style.filled ? rect : rect.insetBy(dx: -half, dy: -half)
        case let .text(string, origin):
            return textFrame(string, at: origin, fontSize: annotation.style.fontSize, measure: measure)
        }
    }

    /// True when `point` lies on what the annotation paints, give or take `tolerance`.
    public static func hits(_ annotation: Annotation, at point: CGPoint, tolerance: CGFloat, measure: TextMeasure) -> Bool {
        let reach = tolerance + CGFloat(annotation.style.lineWidth) / 2
        switch annotation.shape {
        case let .pen(points), let .highlighter(points):
            guard let first = points.first else { return false }
            if points.count == 1 {
                return distance(point, first) <= reach
            }
            return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= reach }
        case let .line(start, end), let .arrow(start, end):
            return distance(from: point, toSegment: start, end) <= reach
        case let .rectangle(rect):
            if annotation.style.filled {
                return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
            let outer = rect.insetBy(dx: -reach, dy: -reach)
            let inner = rect.insetBy(dx: reach, dy: reach)
            return outer.contains(point) && (inner.isNull || inner.isEmpty || !inner.contains(point))
        case let .ellipse(rect):
            let rx = rect.width / 2
            let ry = rect.height / 2
            guard rx > 0, ry > 0 else {
                return rect.insetBy(dx: -reach, dy: -reach).contains(point)
            }
            let nx = (point.x - rect.midX) / rx
            let ny = (point.y - rect.midY) / ry
            let radius = (nx * nx + ny * ny).squareRoot()
            if annotation.style.filled {
                return radius <= 1 + tolerance / min(rx, ry)
            }
            return abs(radius - 1) * min(rx, ry) <= reach
        case let .text(string, origin):
            let frame = textFrame(string, at: origin, fontSize: annotation.style.fontSize, measure: measure)
            return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The shortest distance from `point` to the segment from `a` to `b`.
    public static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return distance(point, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    public static func boundingRect(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Too small to keep: a click instead of a drag with a shape tool.
    public static func isNegligible(_ shape: AnnotationShape) -> Bool {
        switch shape {
        case let .pen(points), let .highlighter(points):
            return points.isEmpty
        case let .line(start, end), let .arrow(start, end):
            return distance(start, end) < 4
        case let .rectangle(rect), let .ellipse(rect):
            return rect.width < 4 && rect.height < 4
        case let .text(string, _):
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
