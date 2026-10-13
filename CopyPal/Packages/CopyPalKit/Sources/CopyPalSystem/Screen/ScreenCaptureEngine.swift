#if os(macOS)
import AppKit
import CoreGraphics
import ScreenCaptureKit
import CopyPalCore

/// One-shot captures through ScreenCaptureKit (macOS 14+), the only non-deprecated
/// way to read the screen. Needs the Screen Recording permission: without it the
/// first call throws `.permissionDenied` (and macOS shows its prompt once).
public enum ScreenCaptureEngine {
    public enum Failure: Error, Sendable, Equatable {
        case permissionDenied
        case displayNotFound
        /// ScreenCaptureKit returned an image of another size and the fallback failed too.
        case unexpectedSize(width: Int, height: Int)
        case underlying(String)
    }

    /// What one screenshot session needs to know about a display.
    public struct Display: Sendable, Equatable {
        public let displayID: CGDirectDisplayID
        /// AppKit coordinates.
        public let frame: CGRect
        /// Device pixels per point.
        public let scale: CGFloat

        public init(displayID: CGDirectDisplayID, frame: CGRect, scale: CGFloat) {
            self.displayID = displayID
            self.frame = frame
            self.scale = scale
        }

        /// The whole display in device pixels.
        public var pixels: PixelRect {
            ScreenshotGeometry.pixels(CGRect(origin: .zero, size: frame.size), scale: scale)
        }
    }

    /// Throws `.permissionDenied` when Screen Recording is not granted (the system
    /// prompt appears on this call the first time), otherwise does nothing.
    public static func checkPermission() async throws {
        _ = try await shareableContent()
    }

    /// The first look at the shareable content takes a few hundred milliseconds; taken
    /// when the hot key is pressed, so the frozen frame is quicker. Errors are ignored
    /// here and reported by the capture itself.
    public static func warmUp() async {
        _ = try? await shareableContent()
    }

    /// The display behind `screen`.
    @MainActor
    public static func display(for screen: NSScreen) -> Display? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return Display(displayID: CGDirectDisplayID(number.uint32Value), frame: screen.frame, scale: screen.backingScaleFactor)
    }

    /// The whole display at its native pixel density, without the cursor and without
    /// the windows in `excludingWindowIDs` (CopyPal's own overlay).
    public static func captureDisplay(_ display: Display, excludingWindowIDs: Set<CGWindowID> = []) async throws -> ImageBox {
        try await capture(display.pixels, of: display, excludingWindowIDs: excludingWindowIDs)
    }

    /// `pixels` of `display` (display-local, top-left origin) at native density. Should
    /// ScreenCaptureKit disagree about the size (ROADMAP R25), the whole display is
    /// captured and the rect cut out, so the result always measures `pixels`.
    public static func capture(_ pixels: PixelRect, of display: Display, excludingWindowIDs: Set<CGWindowID> = []) async throws -> ImageBox {
        let content = try await shareableContent()
        guard let scDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
            throw Failure.displayNotFound
        }
        let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: excluded)
        if #available(macOS 14.2, *) {
            // Without this the menu bar is missing from display captures (R25).
            filter.includeMenuBar = true
        }
        let image = try await captureImage(filter: filter, pixels: pixels, scale: display.scale)
        if image.width == pixels.width, image.height == pixels.height {
            return ImageBox(image)
        }
        let whole = display.pixels
        let wholeImage = try await captureImage(filter: filter, pixels: whole, scale: display.scale)
        guard wholeImage.width == whole.width, wholeImage.height == whole.height,
              let cropped = wholeImage.cropping(to: CGRect(x: pixels.x, y: pixels.y, width: pixels.width, height: pixels.height)) else {
            throw Failure.unexpectedSize(width: image.width, height: image.height)
        }
        return ImageBox(cropped)
    }

    private static func captureImage(filter: SCContentFilter, pixels: PixelRect, scale: CGFloat) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = ScreenshotGeometry.points(pixels, scale: scale)
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.ignoreShadowsDisplay = true
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw map(error)
        }
    }

    private static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw map(error)
        }
    }

    private static func map(_ error: any Error) -> Failure {
        if let failure = error as? Failure { return failure }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied
        }
        return .underlying(nsError.localizedDescription)
    }
}
#endif
