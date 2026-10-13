#if os(macOS)
import AppKit
import CoreGraphics
import ScreenCaptureKit
import CopyPalCore

/// One-shot captures through ScreenCaptureKit (macOS 14+), the only non-deprecated
/// way to read the screen. Needs the Screen Recording permission: without it the
/// first call throws `.permissionDenied` (and macOS shows its prompt once).
public enum ScreenCaptureEngine {
    public enum Failure: Error, Sendable {
        case permissionDenied
        case displayNotFound
        case underlying(String)
    }

    /// What one screenshot session needs to know about a display.
    public struct Display: Sendable {
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
    }

    /// Throws `.permissionDenied` when Screen Recording is not granted (the system
    /// prompt appears on this call the first time), otherwise does nothing.
    public static func checkPermission() async throws {
        _ = try await shareableContent()
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
    public static func captureDisplay(_ display: Display, excludingWindowIDs: Set<CGWindowID> = []) async throws -> CGImage {
        let pixels = ScreenshotGeometry.pixels(CGRect(origin: .zero, size: display.frame.size), scale: display.scale)
        return try await capture(pixels, of: display, excludingWindowIDs: excludingWindowIDs)
    }

    /// `pixels` of `display` (display-local, top-left origin) at native density.
    public static func capture(_ pixels: PixelRect, of display: Display, excludingWindowIDs: Set<CGWindowID> = []) async throws -> CGImage {
        let content = try await shareableContent()
        guard let scDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
            throw Failure.displayNotFound
        }
        let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = ScreenshotGeometry.points(pixels, scale: display.scale)
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
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
