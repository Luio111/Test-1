#if os(macOS)
import CoreGraphics
import CoreText
import CopyPalCore
import Foundation

/// Paints markup (ROADMAP R33) with Core Graphics: into the editor's view and onto the
/// finished picture, so both look the same. Works in points of the picture with the
/// y axis pointing down (a flipped view, or the context `render` sets up).
public enum AnnotationRenderer {
    /// Highlighter ink: see-through, so the text under it stays readable on light and
    /// dark backgrounds alike.
    public static let highlighterAlpha: CGFloat = 0.4

    /// The picture with its markup, in the picture's own pixels. `scale` is pixels per
    /// point (2 on Retina), so sizes match what the editor showed.
    public static func render(_ image: CGImage, scale: CGFloat, annotations: [Annotation]) -> CGImage? {
        guard !annotations.isEmpty else { return image }
        let width = image.width
        let height = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        draw(annotations, in: context)
        return context.makeImage()
    }

    public static func draw(_ annotations: [Annotation], in context: CGContext) {
        for annotation in annotations {
            draw(annotation, in: context)
        }
    }

    public static func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let style = annotation.style
        let width = CGFloat(style.lineWidth)
        let color = cgColor(style.color)
        context.setShouldAntialias(true)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color)
        context.setFillColor(color)
        switch annotation.shape {
        case let .pen(points):
            strokeFreehand(points, width: width, in: context)
        case let .highlighter(points):
            // One path in one go: where the stroke crosses itself it does not get darker.
            context.setAlpha(highlighterAlpha)
            strokeFreehand(points, width: width, in: context)
        case let .line(start, end):
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        case let .arrow(start, end):
            let head = AnnotationGeometry.arrowHead(from: start, to: end, lineWidth: width)
            context.move(to: start)
            context.addLine(to: head.base)
            context.strokePath()
            context.move(to: head.tip)
            context.addLine(to: head.left)
            context.addLine(to: head.right)
            context.closePath()
            context.fillPath()
            // Rounds the head's corners a little, like the shaft's ends.
            context.setLineWidth(min(width, 3))
            context.move(to: head.tip)
            context.addLine(to: head.left)
            context.addLine(to: head.right)
            context.closePath()
            context.strokePath()
        case let .rectangle(rect):
            context.setLineJoin(.miter)
            if style.filled {
                context.fill(rect)
            } else {
                context.stroke(rect)
            }
        case let .ellipse(rect):
            if style.filled {
                context.fillEllipse(in: rect)
            } else {
                context.strokeEllipse(in: rect)
            }
        case let .text(string, origin):
            drawText(string, at: origin, style: style, in: context)
        }
    }

    // MARK: Text

    /// The size of a text's lines in the markup font; the measure the geometry uses.
    public static func textSize(_ text: String, fontSize: Double) -> CGSize {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed(text.isEmpty ? " " : text, fontSize: fontSize, color: cgColor(.black)))
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            nil
        )
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    /// The markup font: the system font in bold, so a comment holds its own on a busy screenshot.
    public static func font(size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, CGFloat(size), nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(size), nil)
    }

    private static func attributed(_ text: String, fontSize: Double, color: CGColor) -> CFAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: fontSize),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return NSAttributedString(string: text, attributes: attributes) as CFAttributedString
    }

    private static func drawText(_ string: String, at origin: CGPoint, style: AnnotationStyle, in context: CGContext) {
        let frame = AnnotationGeometry.textFrame(string, at: origin, fontSize: style.fontSize, measure: textSize)
        let padding = AnnotationGeometry.textPadding(fontSize: style.fontSize)
        let textColor: CGColor
        if style.textBackground {
            let radius = min(frame.height / 2, CGFloat(style.fontSize) * 0.45)
            context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
            textColor = cgColor(style.color.textColorOnTop)
        } else {
            textColor = cgColor(style.color)
            // A soft halo in the opposite brightness keeps bare text readable on any background.
            context.setShadow(offset: .zero, blur: max(2, CGFloat(style.fontSize) * 0.15), color: cgColor(style.color.textColorOnTop, alpha: 0.7))
        }
        guard !string.isEmpty else { return }
        let textRect = frame.insetBy(dx: padding.width, dy: padding.height)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed(string, fontSize: style.fontSize, color: textColor))
        // Core Text lays out with y up: flip around the text's box. The path has room to
        // spare below and to the right, so rounding never drops the last line.
        context.saveGState()
        context.translateBy(x: textRect.minX, y: textRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        let path = CGPath(rect: CGRect(x: 0, y: -4, width: textRect.width + 4, height: textRect.height + 4), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
        context.restoreGState()
    }

    // MARK: Helpers

    public static func cgColor(_ color: AnnotationColor, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: alpha)
    }

    /// A smooth line through the mouse's points: quadratic curves through the midpoints.
    private static func strokeFreehand(_ points: [CGPoint], width: CGFloat, in context: CGContext) {
        guard let first = points.first else { return }
        guard points.count > 1 else {
            context.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
            return
        }
        context.move(to: first)
        if points.count == 2 {
            context.addLine(to: points[1])
        } else {
            for index in 1..<(points.count - 1) {
                let point = points[index]
                let next = points[index + 1]
                context.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), control: point)
            }
            context.addLine(to: points[points.count - 1])
        }
        context.strokePath()
    }
}
#endif
