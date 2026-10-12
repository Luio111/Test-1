import Foundation
import Testing
@testable import CopyPalCore

struct NotchGeometryTests {
    /// 14" MacBook Pro: 1512 × 982 points, notch 185 pt wide, 32 pt high.
    private let macBook = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        auxiliaryLeftWidth: 663.5,
        auxiliaryRightWidth: 663.5
    )

    @Test func notchIsCenteredAtTheTop() {
        let notch = NotchGeometry.notchRect(on: macBook)
        #expect(notch == CGRect(x: 663.5, y: 950, width: 185, height: 32))
    }

    @Test func screenWithoutNotch() {
        let external = ScreenMetrics(frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
        #expect(NotchGeometry.notchRect(on: external) == nil)
    }

    @Test func popupHangsBelowTheNotch() {
        let frame = NotchGeometry.popupFrame(size: CGSize(width: 360, height: 320), on: macBook)
        #expect(frame.midX == 756)
        #expect(frame.maxY == 950)
        #expect(frame.height == 320)
    }

    @Test func popupBelowMenuBarOnExternalScreen() {
        let external = ScreenMetrics(frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), menuBarHeight: 25)
        let frame = NotchGeometry.popupFrame(size: CGSize(width: 360, height: 320), on: external)
        #expect(frame.midX == CGFloat(2792))
        #expect(frame.maxY == 1415)
    }

    @Test func popupStaysInsideSmallScreen() {
        let tiny = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let frame = NotchGeometry.popupFrame(size: CGSize(width: 360, height: 320), on: tiny)
        // Wider than the screen: the right-edge clamp wins, the popup stays reachable from the top.
        #expect(frame.maxX == CGFloat(300))
        #expect(frame.minY == CGFloat(0))
    }
}

struct LatencySummaryTests {
    @Test func emptyHasNoSummary() {
        #expect(LatencySummary(milliseconds: []) == nil)
    }

    @Test func oddCount() {
        let summary = LatencySummary(milliseconds: [30, 10, 20])
        #expect(summary?.median == 20)
        #expect(summary?.p90 == 30)
        #expect(summary?.max == 30)
        #expect(summary?.count == 3)
    }

    @Test func evenCountAndPercentile() {
        let values = (1...10).map(Double.init)
        let summary = LatencySummary(milliseconds: values)
        #expect(summary?.median == 5.5)
        #expect(summary?.p90 == 9)
        #expect(summary?.max == 10)
    }
}
