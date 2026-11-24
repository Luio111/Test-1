#if os(macOS)
import CoreGraphics

/// A captured image on its way between the capture task and the main actor. A
/// `CGImage` is immutable, so sharing it is safe; the SDK does not say so, hence the box.
public final class ImageBox: @unchecked Sendable {
    public let image: CGImage

    public init(_ image: CGImage) {
        self.image = image
    }

    public var width: Int { image.width }
    public var height: Int { image.height }
}
#endif
