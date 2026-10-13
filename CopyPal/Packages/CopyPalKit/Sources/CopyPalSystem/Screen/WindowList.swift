#if os(macOS)
import AppKit
import CoreGraphics
import CopyPalCore

/// The windows on screen, frontmost first, for snapping a screenshot to a window (M11).
/// Needs no permission; titles are only filled in with Screen Recording. The call is
/// comparatively expensive, so it is made once per screenshot, not per mouse move.
public enum WindowList {
    @MainActor
    public static func onScreen() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { info(from: $0, primaryHeight: primaryHeight) }
    }

    /// One entry of the window list (`kCGWindow…` keys) as a `WindowInfo`.
    static func info(from info: [String: Any], primaryHeight: CGFloat) -> WindowInfo? {
        guard let number = info[kCGWindowNumber as String] as? Int,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            return nil
        }
        return WindowInfo(
            id: UInt32(truncatingIfNeeded: number),
            frame: ScreenshotGeometry.flipped(bounds, primaryHeight: primaryHeight),
            layer: info[kCGWindowLayer as String] as? Int ?? 0,
            alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
            ownerPID: Int32(truncatingIfNeeded: info[kCGWindowOwnerPID as String] as? Int ?? 0),
            title: info[kCGWindowName as String] as? String
        )
    }

    /// The number of the window of any app under `point` (AppKit coordinates), looking
    /// below the window `windowNumber` (0: from the top); 0 when there is none. Used
    /// before every scroll step to make sure the content under the selection is still
    /// the window the selection was made on.
    @MainActor
    public static func windowNumber(at point: CGPoint, belowWindowNumber windowNumber: Int) -> Int {
        NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: windowNumber)
    }
}
#endif
