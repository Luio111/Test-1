#if os(macOS)
import CopyPalCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image helpers on ImageIO (thread-safe, no AppKit drawing).
public enum ImageConversion {
    /// Any image data ImageIO can read (TIFF, JPEG, HEIC …) as PNG.
    public static func png(fromImageData data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return encodePNG(image)
    }

    /// A PNG thumbnail whose longer side is at most `maxPixelSize` (ROADMAP M6: 256 px).
    public static func thumbnail(fromImageData data: Data, maxPixelSize: Int = 256) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encodePNG(image)
    }

    // MARK: Screenshots (M11)

    /// PNG of a captured image. `scale` 2 tags it 144 dpi, so Preview shows a Retina
    /// screenshot at its real size.
    public static func png(_ image: CGImage, scale: CGFloat) -> Data? {
        let dpi = 72 * scale
        return encode(image, type: .png, properties: [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi])
    }

    /// TIFF for apps that paste only that (Safari, Mail); PNG alone is not enough there.
    public static func tiff(_ image: CGImage, scale: CGFloat) -> Data? {
        let dpi = 72 * scale
        return encode(image, type: .tiff, properties: [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi])
    }

    /// The image's pixels as 8-bit BGRA for the stitcher and the region detector.
    public static func pixelBuffer(_ image: CGImage) -> PixelBuffer? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * PixelBuffer.bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bgraBitmapInfo
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? PixelBuffer(width: width, height: height, bytesPerRow: bytesPerRow, bgra: bytes) : nil
    }

    /// A BGRA buffer back as an image (the stitched screenshot).
    public static func cgImage(_ buffer: PixelBuffer) -> CGImage? {
        guard !buffer.isEmpty,
              let provider = CGDataProvider(data: Data(buffer.bgra) as CFData) else {
            return nil
        }
        return CGImage(
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: buffer.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bgraBitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Brightness per `cellPixels` × `cellPixels` block for the region detector, drawn
    /// through a gray context that averages – no full BGRA copy of the display.
    public static func lumaPlane(_ image: CGImage, cellPixels: Int) -> LumaPlane? {
        let cell = max(cellPixels, 1)
        let width = max((image.width + cell - 1) / cell, 1)
        let height = max((image.height + cell - 1) / cell, 1)
        var luma = [UInt8](repeating: 0, count: width * height)
        let drawn = luma.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? LumaPlane(width: width, height: height, cell: cell, luma: luma) : nil
    }

    /// The image at `factor` of its size (½ for screenshots too large for the history).
    public static func downscaled(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = max(Int((CGFloat(image.width) * factor).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * factor).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bgraBitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A PNG and the image it shows, halved until the PNG fits `maxBytes`.
    public struct FittedPNG: Sendable {
        public let data: Data
        public let image: ImageBox
        /// Device pixels per point of `image` (halved with it, so the DPI stays honest).
        public let scale: CGFloat
        public let downscaled: Bool
    }

    /// `image` as PNG of at most `maxBytes` (the history's limit), halving it up to
    /// `maximumHalvings` times. The last attempt is returned even when it is still too
    /// large, flagged `downscaled`, so the caller can decide to keep it off the history.
    public static func pngFitting(_ image: CGImage, scale: CGFloat, maxBytes: Int, maximumHalvings: Int = 3) -> FittedPNG? {
        var current = image
        var currentScale = scale
        var halvings = 0
        while true {
            guard let data = png(current, scale: currentScale) else { return nil }
            if data.count <= maxBytes || halvings >= maximumHalvings {
                return FittedPNG(data: data, image: ImageBox(current), scale: currentScale, downscaled: halvings > 0)
            }
            guard let smaller = downscaled(current, by: 0.5) else { return nil }
            current = smaller
            currentScale /= 2
            halvings += 1
        }
    }

    /// Premultiplied BGRA, the byte order ScreenCaptureKit and the display use.
    private static var bgraBitmapInfo: UInt32 {
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        encode(image, type: .png, properties: nil)
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any]?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
#endif
