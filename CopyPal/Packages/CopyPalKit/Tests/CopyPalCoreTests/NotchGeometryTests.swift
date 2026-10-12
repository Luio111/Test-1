import Foundation
// CGRect's members (minX, width, …) come from CoreGraphics on Apple platforms;
// Foundation alone no longer provides them with Xcode 26.
#if canImport(CoreGraphics)
import CoreGraphics
#endif
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

struct ScreenChoiceTests {
    let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    @Test func keyWindowDecides() {
        let window = CGRect(x: 1600, y: 100, width: 800, height: 600)
        #expect(NotchGeometry.screenIndex(screens: [builtIn, external], keyWindowFrame: window, mouseLocation: CGPoint(x: 10, y: 10)) == 1)
    }

    @Test func windowAcrossScreensUsesLargerPart() {
        let window = CGRect(x: 1300, y: 100, width: 800, height: 600)
        #expect(NotchGeometry.screenIndex(screens: [builtIn, external], keyWindowFrame: window, mouseLocation: .zero) == 1)
    }

    @Test func mouseWhenNoWindow() {
        #expect(NotchGeometry.screenIndex(screens: [builtIn, external], keyWindowFrame: nil, mouseLocation: CGPoint(x: 2000, y: 500)) == 1)
        #expect(NotchGeometry.screenIndex(screens: [builtIn, external], keyWindowFrame: nil, mouseLocation: CGPoint(x: 100, y: 500)) == 0)
    }

    @Test func fallbackAndEmpty() {
        #expect(NotchGeometry.screenIndex(screens: [builtIn], keyWindowFrame: nil, mouseLocation: CGPoint(x: -500, y: -500)) == 0)
        #expect(NotchGeometry.screenIndex(screens: [], keyWindowFrame: nil, mouseLocation: .zero) == nil)
    }

    @Test func hudOnNotchCoversIt() {
        let macBook = ScreenMetrics(frame: builtIn, safeAreaTop: 32, auxiliaryLeftWidth: 663.5, auxiliaryRightWidth: 663.5)
        let frame = NotchGeometry.hudFrame(size: CGSize(width: 200, height: 28), on: macBook)
        #expect(frame.maxY == CGFloat(982))
        #expect(frame.midX == CGFloat(756))
        #expect(frame.height == CGFloat(60))
        #expect(frame.width >= 185)
    }

    @Test func hudBelowMenuBar() {
        let screen = ScreenMetrics(frame: external, menuBarHeight: 25)
        let frame = NotchGeometry.hudFrame(size: CGSize(width: 200, height: 28), on: screen)
        #expect(frame.maxY == CGFloat(1407))
        #expect(frame.midX == CGFloat(2792))
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
