#if os(macOS)
import AppKit
import CoreGraphics
import ImageIO
import Testing
import CopyPalCore
@testable import CopyPalSystem

/// The macOS adapters of the screenshot feature that need no permission (M11).
struct ScreenshotSystemTests {
    private func pattern(width: Int = 4, height: Int = 4) -> PixelBuffer {
        var buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                buffer.fill(
                    PixelRect(x: x, y: y, width: 1, height: 1),
                    b: UInt8(truncatingIfNeeded: x * 37),
                    g: UInt8(truncatingIfNeeded: y * 53),
                    r: UInt8(truncatingIfNeeded: (x + y) * 29)
                )
            }
        }
        return buffer
    }

    @Test func pixelBufferAndImageRoundTrip() throws {
        let buffer = pattern()
        let image = try #require(ImageConversion.cgImage(buffer))
        #expect(image.width == 4 && image.height == 4)
        let back = try #require(ImageConversion.pixelBuffer(image))
        #expect(back.width == 4 && back.height == 4)
        for y in 0..<4 {
            let expected = Array(buffer.row(y))
            let actual = Array(back.row(y))
            #expect(expected.count == actual.count)
            let maxDifference = zip(expected, actual).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(maxDifference <= 1, "row \(y)")
        }
    }

    @Test func pngAndTiffCarryTheRetinaDPI() throws {
        let image = try #require(ImageConversion.cgImage(pattern()))
        let png = try #require(ImageConversion.png(image, scale: 2))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 4)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 4)
        let dpi = properties[kCGImagePropertyDPIWidth] as? Double ?? 0
        #expect(abs(dpi - 144) < 1)

        let tiff = try #require(ImageConversion.tiff(image, scale: 2))
        let tiffSource = try #require(CGImageSourceCreateWithData(tiff as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(tiffSource, 0, nil)?.width == 4)
    }

    @Test func lumaPlaneAveragesCells() throws {
        var buffer = PixelBuffer(width: 8, height: 4)
        buffer.fill(PixelRect(x: 4, y: 0, width: 4, height: 4), b: 255, g: 255, r: 255)
        let image = try #require(ImageConversion.cgImage(buffer))
        let plane = try #require(ImageConversion.lumaPlane(image, cellPixels: 2))
        #expect(plane.width == 4 && plane.height == 2 && plane.cell == 2)
        // The cells next to the boundary may blend; the outer ones are pure.
        #expect(plane[0, 0] < 16 && plane[0, 1] < 16)
        #expect(plane[3, 0] > 239 && plane[3, 1] > 239)
    }

    @Test func downscalingHalvesTheImage() throws {
        let image = try #require(ImageConversion.cgImage(pattern(width: 8, height: 4)))
        let half = try #require(ImageConversion.downscaled(image, by: 0.5))
        #expect(half.width == 4 && half.height == 2)
    }

    @Test func pngFittingHalvesUntilItFits() throws {
        let image = try #require(ImageConversion.cgImage(pattern(width: 64, height: 64)))
        let generous = try #require(ImageConversion.pngFitting(image, scale: 2, maxBytes: 10_000_000))
        #expect(!generous.downscaled && generous.image.width == 64 && generous.scale == 2)
        let tight = try #require(ImageConversion.pngFitting(image, scale: 2, maxBytes: 1))
        #expect(tight.downscaled && tight.image.width == 8 && tight.scale == 0.25)
    }

    @Test func scrollEventsCarryDeltaAndMarker() throws {
        let event = try #require(ScrollSynthesizer.makeEvent(delta: -120, units: .pixel, at: CGPoint(x: 10, y: 20)))
        #expect(event.type == .scrollWheel)
        let pointDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        #expect(pointDelta < 0 || fixedDelta < 0)
        #expect(event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
        #expect(PasteSynthesizer.isOwn(event))
        #expect(event.location == CGPoint(x: 10, y: 20))

        let lines = try #require(ScrollSynthesizer.makeEvent(delta: 3, units: .line, at: .zero))
        #expect(lines.getIntegerValueField(.scrollWheelEventDeltaAxis1) > 0)
        #expect(ScrollPlanner.chunks(deltaPoints: 400, direction: .down, reversed: false) == [-160, -160, -80])
    }

    @Test func permissionPreflightDoesNotPrompt() {
        // Only that it answers; the value depends on the machine.
        let state = ScreenCapturePermission.state
        #expect(state == .granted || state == .denied)
    }

    @Test @MainActor func windowListMapsTheWindowServerDictionaries() {
        // May be empty on a runner; must not crash.
        _ = WindowList.onScreen()

        let info: [String: Any] = [
            kCGWindowNumber as String: 42,
            kCGWindowBounds as String: ["X": 10, "Y": 20, "Width": 300, "Height": 200],
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1.0,
            kCGWindowOwnerPID as String: 123,
            kCGWindowName as String: "Fixture",
        ]
        let window = WindowList.info(from: info, primaryHeight: 1000)
        #expect(window?.id == 42)
        #expect(window?.ownerPID == 123)
        #expect(window?.title == "Fixture")
        #expect(window?.frame == CGRect(x: 10, y: 780, width: 300, height: 200))
        #expect(WindowList.info(from: [:], primaryHeight: 1000) == nil)
    }

    @Test func displayPixelsCoverTheWholeScreen() {
        let display = ScreenCaptureEngine.Display(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
        #expect(display.pixels == PixelRect(x: 0, y: 0, width: 3024, height: 1964))
    }
}
#endif
