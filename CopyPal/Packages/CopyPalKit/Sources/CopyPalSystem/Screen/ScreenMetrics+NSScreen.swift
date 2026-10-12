#if os(macOS)
import AppKit
import CopyPalCore

extension ScreenMetrics {
    @MainActor
    public init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: max(screen.frame.maxY - screen.visibleFrame.maxY, 0)
        )
    }
}
#endif
