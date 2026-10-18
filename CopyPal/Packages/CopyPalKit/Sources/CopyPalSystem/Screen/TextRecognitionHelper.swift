#if os(macOS)
import Foundation

/// The interface of CopyPal's text recognition helper, an XPC service inside the app
/// bundle (`Contents/XPCServices`, ADR 0005). Vision keeps its models in memory after
/// the first request (about 80 MB); in the helper they leave with the process, which
/// ends as soon as CopyPal closes the connection (ROADMAP R32).
@objc public protocol TextRecognitionXPC {
    /// The text in `imageData` (PNG, TIFF …) via ``TextRecognizer``; `nil` when the
    /// image cannot be read.
    func recognizeText(in imageData: Data, maxPixels: Int, reply: @escaping @Sendable (String?) -> Void)
}

public enum TextRecognitionHelper {
    /// The helper's bundle in CopyPal.app/Contents/XPCServices (project.yml).
    public static let bundleName = "CopyPalTextRecognition.xpc"

    public static func makeInterface() -> NSXPCInterface {
        NSXPCInterface(with: TextRecognitionXPC.self)
    }
}
#endif
