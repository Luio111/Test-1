#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Vision
import CopyPalCore

/// The text in an image, recognized with Vision on this Mac (no network): accurate,
/// German and English, without language correction so codes and IBANs stay as they
/// are. Synchronous and comparatively slow – call it off the main thread. The app
/// calls it in its helper process (``TextRecognitionXPC``), not in its own.
public enum TextRecognizer {
    /// Larger pictures are read scaled down to this many pixels.
    public static let defaultMaxPixels = 16_000_000

    public static func text(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["de-DE", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, box: observation.boundingBox)
        }
        return RecognizedText.join(lines)
    }

    /// The same for encoded image data (PNG, TIFF …). Pictures above `maxPixels` are
    /// read scaled down to that size, decoded straight at the smaller size: a long
    /// stitched screenshot never needs hundreds of megabytes just to be searchable.
    public static func text(inImageData data: Data, maxPixels: Int = defaultMaxPixels) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let image: CGImage?
        if let size = pixelSize(of: source), size.width * size.height > maxPixels {
            let factor = (Double(maxPixels) / Double(size.width * size.height)).squareRoot()
            let longestSide = Int((Double(max(size.width, size.height)) * factor).rounded(.down))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(longestSide, 1),
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return image.flatMap { text(in: $0) }
    }

    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }
}
#endif
