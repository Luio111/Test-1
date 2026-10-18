#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Vision
import CopyPalCore

/// The text in an image, recognized with Vision on this Mac (no network): accurate,
/// German and English, without language correction so codes and IBANs stay as they
/// are. Synchronous and comparatively slow – call it off the main thread.
public enum TextRecognizer {
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

    /// The same for encoded image data (PNG, TIFF …).
    public static func text(inImageData data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return text(in: image)
    }
}
#endif
