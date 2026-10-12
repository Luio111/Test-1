import Foundation
// CGRect's members (minX, width, …) come from CoreGraphics on Apple platforms;
// Foundation alone no longer provides them with Xcode 26.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The parts of `NSScreen` the popup placement needs, without AppKit.
public struct ScreenMetrics: Sendable, Equatable {
    /// Screen frame in global coordinates (origin bottom-left, like AppKit).
    public var frame: CGRect
    /// `safeAreaInsets.top`: > 0 on displays with a camera housing.
    public var safeAreaTop: CGFloat
    /// Widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (the menu bar parts
    /// left and right of the notch). Only widths are used, so it does not matter in
    /// which coordinate space AppKit reports those rects.
    public var auxiliaryLeftWidth: CGFloat?
    public var auxiliaryRightWidth: CGFloat?
    /// Height of the menu bar area on screens without a notch.
    public var menuBarHeight: CGFloat

    public init(
        frame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryLeftWidth: CGFloat? = nil,
        auxiliaryRightWidth: CGFloat? = nil,
        menuBarHeight: CGFloat = 24
    ) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.menuBarHeight = menuBarHeight
    }
}

public enum NotchGeometry {
    /// The camera housing in global coordinates, or nil on screens without a notch.
    public static func notchRect(on screen: ScreenMetrics) -> CGRect? {
        guard screen.safeAreaTop > 0,
              let left = screen.auxiliaryLeftWidth,
              let right = screen.auxiliaryRightWidth else {
            return nil
        }
        let width = screen.frame.width - left - right
        guard width > 0 else { return nil }
        return CGRect(
            x: screen.frame.minX + left,
            y: screen.frame.maxY - screen.safeAreaTop,
            width: width,
            height: screen.safeAreaTop
        )
    }

    /// Popup frame: horizontally centered on the notch (or the screen), hanging
    /// directly below the notch (or the menu bar), kept inside the screen.
    public static func popupFrame(size: CGSize, on screen: ScreenMetrics) -> CGRect {
        let notch = notchRect(on: screen)
        let centerX = notch?.midX ?? screen.frame.midX
        let top = screen.frame.maxY - (notch?.height ?? screen.menuBarHeight)

        var x = (centerX - size.width / 2).rounded()
        x = min(max(x, screen.frame.minX), screen.frame.maxX - size.width)
        let y = max(top - size.height, screen.frame.minY)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
