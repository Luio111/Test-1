import Foundation

/// A window on screen as the window server lists it (`CGWindowListCopyWindowInfo`),
/// with its frame already in AppKit coordinates.
public struct WindowInfo: Sendable, Hashable {
    public var id: UInt32
    /// AppKit coordinates (origin bottom left of the primary display).
    public var frame: CGRect
    /// 0 for ordinary windows; menus, the Dock and overlays sit on other layers.
    public var layer: Int
    public var alpha: Double
    public var ownerPID: Int32
    /// Only known with the Screen Recording permission.
    public var title: String?

    public init(id: UInt32, frame: CGRect, layer: Int = 0, alpha: Double = 1, ownerPID: Int32, title: String? = nil) {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
        self.ownerPID = ownerPID
        self.title = title
    }
}

/// Which windows a screenshot can snap to, and which one is under the pointer (M11).
public enum WindowGeometry {
    /// Smaller windows are tooltips, badges and helper panels, not targets.
    public static let minimumSize = CGSize(width: 60, height: 40)

    /// The windows worth snapping to, frontmost first: ordinary layer, visible, large
    /// enough, not CopyPal's own, and each window once (the list repeats ids).
    public static func snapTargets(_ windows: [WindowInfo], excludingPID: Int32? = nil) -> [WindowInfo] {
        var seen = Set<UInt32>()
        return windows.filter { window in
            guard window.layer == 0,
                  window.alpha > 0.05,
                  window.frame.width >= minimumSize.width,
                  window.frame.height >= minimumSize.height,
                  window.ownerPID != excludingPID,
                  !seen.contains(window.id) else {
                return false
            }
            seen.insert(window.id)
            return true
        }
    }

    /// The frontmost of `targets` that contains `point` (AppKit).
    public static func window(at point: CGPoint, in targets: [WindowInfo]) -> WindowInfo? {
        targets.first { $0.frame.contains(point) }
    }
}
