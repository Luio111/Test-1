#if os(macOS)
import CoreGraphics
import Testing
import CopyPalCore
@testable import CopyPalSystem

/// The markup painted onto a picture (ROADMAP R33): where it lands, how it looks.
struct AnnotationRendererTests {
    private struct Pixels {
        let bytes: [UInt8]
        let width: Int

        /// sRGB components 0…255 at a pixel, origin top left.
        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let index = (y * width + x) * 4
            return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
        }

        func isWhite(_ x: Int, _ y: Int) -> Bool {
            let pixel = rgb(x, y)
            return pixel.r > 245 && pixel.g > 245 && pixel.b > 245
        }
    }

    private func plain(width: Int, height: Int, white: Bool = true) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let level: CGFloat = white ? 1 : 0
        context.setFillColor(CGColor(srgbRed: level, green: level, blue: level, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func pixels(_ image: CGImage) throws -> Pixels {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(drawn)
        return Pixels(bytes: bytes, width: image.width)
    }

    @Test func shapesLandWherePointsSayOnARetinaPicture() throws {
        // 100 × 50 pt at 2× = 200 × 100 px; a filled box near the top left.
        let box = Annotation(shape: .rectangle(CGRect(x: 10, y: 5, width: 20, height: 10)), style: AnnotationStyle(color: .red, lineWidth: 4, filled: true))
        let image = try #require(AnnotationRenderer.render(try plain(width: 200, height: 100), scale: 2, annotations: [box]))
        #expect(image.width == 200 && image.height == 100)
        let result = try pixels(image)
        // Points (20, 10) → pixels (40, 20): red, the y axis pointing down.
        let inside = result.rgb(40, 20)
        #expect(inside.r > 230 && inside.g < 90 && inside.b < 90)
        #expect(result.isWhite(40, 100 - 20))
        #expect(result.isWhite(10, 10))
        #expect(result.isWhite(70, 20))
    }

    @Test func outlinesLeaveTheInsideFree() throws {
        let ring = Annotation(shape: .ellipse(CGRect(x: 10, y: 10, width: 80, height: 80)), style: AnnotationStyle(color: .blue, lineWidth: 6))
        let result = try pixels(try #require(AnnotationRenderer.render(try plain(width: 100, height: 100), scale: 1, annotations: [ring])))
        #expect(result.isWhite(50, 50))
        let edge = result.rgb(50, 10)
        #expect(edge.b > 200 && edge.r < 60)
    }

    @Test func theHighlighterIsSeeThrough() throws {
        let stroke = Annotation(shape: .highlighter([CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)]), style: AnnotationStyle(color: .yellow, lineWidth: 20))
        let onBlack = try pixels(try #require(AnnotationRenderer.render(try plain(width: 100, height: 100, white: false), scale: 1, annotations: [stroke])))
        let pixel = onBlack.rgb(50, 50)
        // 40 % yellow over black: visible, but far from full yellow.
        #expect(pixel.r > 60 && pixel.r < 150)
        #expect(pixel.b < 20)
        // A stroke back over itself is no darker than once.
        let twice = Annotation(shape: .highlighter([CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50), CGPoint(x: 0, y: 50)]), style: stroke.style)
        let overlapped = try pixels(try #require(AnnotationRenderer.render(try plain(width: 100, height: 100, white: false), scale: 1, annotations: [twice])))
        #expect(abs(overlapped.rgb(50, 50).r - pixel.r) < 6)
    }

    @Test func textStaysInsideItsBox() throws {
        var style = AnnotationStyle.defaults(for: .text)
        style.color = .black
        style.textBackground = false
        let origin = CGPoint(x: 20, y: 30)
        let text = Annotation(shape: .text("Hallo", at: origin), style: style)
        let frame = AnnotationGeometry.textFrame("Hallo", at: origin, fontSize: style.fontSize, measure: AnnotationRenderer.textSize)
        let result = try pixels(try #require(AnnotationRenderer.render(try plain(width: 300, height: 120), scale: 1, annotations: [text])))
        var inside = 0
        var outside = 0
        for y in 0..<120 {
            for x in 0..<300 where !result.isWhite(x, y) {
                if frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: y)) {
                    inside += 1
                } else {
                    outside += 1
                }
            }
        }
        #expect(inside > 100)
        #expect(outside == 0)
    }

    @Test func aBubbleCarriesWhiteTextOnRed() throws {
        let origin = CGPoint(x: 10, y: 10)
        let text = Annotation(shape: .text("WWW", at: origin), style: .defaults(for: .text))
        let frame = AnnotationGeometry.textFrame("WWW", at: origin, fontSize: 20, measure: AnnotationRenderer.textSize)
        let result = try pixels(try #require(AnnotationRenderer.render(try plain(width: 200, height: 80), scale: 1, annotations: [text])))
        // The bubble's left edge, halfway down: red. Somewhere in the letters: white.
        let edge = result.rgb(Int(frame.minX) + 3, Int(frame.midY))
        #expect(edge.r > 230 && edge.g < 90)
        var whiteInside = 0
        for y in Int(frame.minY + 4)..<Int(frame.maxY - 4) {
            for x in Int(frame.minX + 6)..<Int(frame.maxX - 6) where result.isWhite(x, y) {
                whiteInside += 1
            }
        }
        #expect(whiteInside > 20)
    }

    @Test func textGrowsWithItsSizeAndLines() {
        let small = AnnotationRenderer.textSize("Hallo", fontSize: 12)
        let large = AnnotationRenderer.textSize("Hallo", fontSize: 36)
        #expect(large.width > small.width * 2.5)
        let twoLines = AnnotationRenderer.textSize("Hallo\nWelt", fontSize: 12)
        #expect(twoLines.height > small.height * 1.8)
        #expect(AnnotationRenderer.textSize("", fontSize: 12).height > 0)
    }

    @Test func arrowsEndAtTheirTip() throws {
        let arrow = Annotation(shape: .arrow(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 150, y: 50)), style: AnnotationStyle(color: .red, lineWidth: 5))
        let result = try pixels(try #require(AnnotationRenderer.render(try plain(width: 200, height: 100), scale: 1, annotations: [arrow])))
        #expect(!result.isWhite(146, 50))
        #expect(!result.isWhite(80, 50))
        #expect(result.isWhite(160, 50))
        // The head is wider than the shaft.
        #expect(!result.isWhite(135, 58))
        #expect(result.isWhite(80, 58))
    }

    @Test func noMarkupKeepsThePicture() throws {
        let image = try plain(width: 10, height: 10)
        #expect(AnnotationRenderer.render(image, scale: 2, annotations: []) === image)
    }
}
#endif
