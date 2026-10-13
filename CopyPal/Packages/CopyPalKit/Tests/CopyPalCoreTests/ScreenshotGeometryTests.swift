import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import CopyPalCore

struct ScreenshotGeometryTests {
    // A 1512×982 MacBook display as the primary screen, a 1920×1080 monitor to its right.
    private let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let secondary = CGRect(x: 1512, y: -98, width: 1920, height: 1080)

    @Test func flippingIsItsOwnInverse() {
        let rect = CGRect(x: 100, y: 200, width: 300, height: 50)
        let topLeft = ScreenshotGeometry.flipped(rect, primaryHeight: primary.height)
        #expect(topLeft == CGRect(x: 100, y: 982 - 250, width: 300, height: 50))
        #expect(ScreenshotGeometry.flipped(topLeft, primaryHeight: primary.height) == rect)
        #expect(ScreenshotGeometry.flipped(CGPoint(x: 10, y: 982), primaryHeight: primary.height) == CGPoint(x: 10, y: 0))
    }

    @Test func windowBoundsFromTheWindowServerBecomeAppKitRects() {
        // kCGWindowBounds of a window 40 pt below the top edge of the primary display.
        let bounds = CGRect(x: 50, y: 40, width: 600, height: 400)
        let appKit = ScreenshotGeometry.flipped(bounds, primaryHeight: primary.height)
        // 40 pt below the top edge → the AppKit rect ends 40 pt below the top: 982 − 40 − 400.
        #expect(appKit == CGRect(x: 50, y: 542, width: 600, height: 400))
    }

    @Test func displayLocalRectIsRelativeToTheDisplaysTopLeft() {
        // On the secondary display, 10 pt from its left edge and 20 pt below its top edge.
        let rect = CGRect(x: 1522, y: secondary.maxY - 20 - 100, width: 200, height: 100)
        let local = ScreenshotGeometry.displayLocal(rect, in: secondary)
        #expect(local == CGRect(x: 10, y: 20, width: 200, height: 100))
        #expect(ScreenshotGeometry.appKit(fromDisplayLocal: local, in: secondary) == rect)
    }

    @Test func pixelsCoverTheWholeRectAtRetinaScale() {
        let local = CGRect(x: 10.25, y: 20, width: 100.5, height: 50)
        let pixels = ScreenshotGeometry.pixels(local, scale: 2)
        #expect(pixels == PixelRect(x: 20, y: 40, width: 202, height: 100))
        // Back in points the rect is at least as large as the original.
        let points = ScreenshotGeometry.points(pixels, scale: 2)
        #expect(points.minX <= local.minX && points.maxX >= local.maxX)
        #expect(points.minY <= local.minY && points.maxY >= local.maxY)
    }

    @Test func pixelsIgnoreFloatingPointNoise() {
        let noisy = CGRect(x: 100.00000001, y: 0, width: 300.00000002, height: 200)
        #expect(ScreenshotGeometry.pixels(noisy, scale: 2) == PixelRect(x: 200, y: 0, width: 600, height: 400))
        #expect(ScreenshotGeometry.pixels(CGRect(x: 0, y: 0, width: 0, height: 10), scale: 2).isEmpty)
    }

    @Test func clampKeepsTheOverlap() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(ScreenshotGeometry.clamp(CGRect(x: 50, y: 50, width: 100, height: 100), to: bounds) == CGRect(x: 50, y: 50, width: 50, height: 50))
        #expect(ScreenshotGeometry.clamp(CGRect(x: 200, y: 200, width: 10, height: 10), to: bounds) == .zero)
        // A negative-size rect is standardized first.
        #expect(ScreenshotGeometry.clamp(CGRect(x: 60, y: 60, width: -20, height: -20), to: bounds) == CGRect(x: 40, y: 40, width: 20, height: 20))
    }

    @Test func dragRectsFollowThePointerInEveryDirection() {
        let anchor = CGPoint(x: 100, y: 100)
        #expect(ScreenshotGeometry.dragRect(anchor: anchor, current: CGPoint(x: 160, y: 140)) == CGRect(x: 100, y: 100, width: 60, height: 40))
        #expect(ScreenshotGeometry.dragRect(anchor: anchor, current: CGPoint(x: 40, y: 60)) == CGRect(x: 40, y: 60, width: 60, height: 40))
        #expect(ScreenshotGeometry.dragRect(anchor: anchor, current: anchor).isEmpty)
    }

    @Test func shiftMakesTheDragSquareTowardsThePointer() {
        let anchor = CGPoint(x: 100, y: 100)
        #expect(ScreenshotGeometry.dragRect(anchor: anchor, current: CGPoint(x: 160, y: 120), square: true) == CGRect(x: 100, y: 100, width: 60, height: 60))
        #expect(ScreenshotGeometry.dragRect(anchor: anchor, current: CGPoint(x: 80, y: 40), square: true) == CGRect(x: 40, y: 40, width: 60, height: 60))
    }

    @Test func optionGrowsTheDragFromTheCenter() {
        let anchor = CGPoint(x: 100, y: 100)
        #expect(ScreenshotGeometry.dragRect(anchor: anchor, current: CGPoint(x: 130, y: 110), fromCenter: true) == CGRect(x: 70, y: 90, width: 60, height: 20))
        #expect(ScreenshotGeometry.dragRect(anchor: anchor, current: CGPoint(x: 130, y: 110), square: true, fromCenter: true) == CGRect(x: 70, y: 70, width: 60, height: 60))
    }

    @Test func movingStopsAtTheEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect = CGRect(x: 10, y: 10, width: 30, height: 30)
        #expect(ScreenshotGeometry.moved(rect, dx: 5, dy: -5, within: bounds) == CGRect(x: 15, y: 5, width: 30, height: 30))
        #expect(ScreenshotGeometry.moved(rect, dx: 500, dy: 500, within: bounds) == CGRect(x: 70, y: 70, width: 30, height: 30))
        #expect(ScreenshotGeometry.moved(rect, dx: -500, dy: 0, within: bounds) == CGRect(x: 0, y: 10, width: 30, height: 30))
    }
}

struct WindowGeometryTests {
    private let own: Int32 = 4242

    private func window(_ id: UInt32, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, layer: Int = 0, alpha: Double = 1, pid: Int32 = 1) -> WindowInfo {
        WindowInfo(id: id, frame: CGRect(x: x, y: y, width: w, height: h), layer: layer, alpha: alpha, ownerPID: pid)
    }

    @Test func snapTargetsKeepOrdinaryVisibleWindowsOnce() {
        let windows = [
            window(1, 0, 0, 800, 600),
            window(2, 0, 0, 800, 600, layer: 25),          // menu bar item
            window(3, 0, 0, 800, 600, alpha: 0.01),        // invisible
            window(4, 0, 0, 50, 30),                       // tooltip-sized
            window(5, 0, 0, 800, 600, pid: 4242),          // CopyPal's own overlay
            window(1, 0, 0, 800, 600),                     // repeated id
            window(6, 100, 100, 300, 200),
        ]
        let targets = WindowGeometry.snapTargets(windows, excludingPID: own)
        #expect(targets.map(\.id) == [1, 6])
    }

    @Test func theFrontmostWindowUnderThePointerWins() {
        let back = window(1, 0, 0, 800, 600)
        let front = window(2, 100, 100, 300, 200)
        let targets = WindowGeometry.snapTargets([front, back])
        #expect(WindowGeometry.window(at: CGPoint(x: 150, y: 150), in: targets)?.id == 2)
        #expect(WindowGeometry.window(at: CGPoint(x: 50, y: 50), in: targets)?.id == 1)
        #expect(WindowGeometry.window(at: CGPoint(x: 900, y: 900), in: targets) == nil)
    }
}

struct ScreenshotKeyMapTests {
    @Test func knownKeysAreMapped() {
        #expect(ScreenshotKeyMap.key(forKeyCode: 53) == .escape)
        #expect(ScreenshotKeyMap.key(forKeyCode: 36) == .confirm)
        #expect(ScreenshotKeyMap.key(forKeyCode: 76) == .confirm)
        #expect(ScreenshotKeyMap.key(forKeyCode: 49) == .space)
        #expect(ScreenshotKeyMap.key(forKeyCode: 48) == .tab)
        #expect(ScreenshotKeyMap.key(forKeyCode: 126) == .up)
        #expect(ScreenshotKeyMap.key(forKeyCode: 125) == .down)
        #expect(ScreenshotKeyMap.key(forKeyCode: 123) == .left)
        #expect(ScreenshotKeyMap.key(forKeyCode: 124) == .right)
        #expect(ScreenshotKeyMap.key(forKeyCode: 0) == nil)
    }
}
