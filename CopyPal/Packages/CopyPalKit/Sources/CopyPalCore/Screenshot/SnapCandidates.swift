import Foundation

/// What the pointer is over, from the smallest thing outward (M11).
public enum SnapKind: Sendable, Equatable {
    /// A button, an image, a line of text …
    case element
    /// Several lines of text that belong together.
    case block
    /// A flat area such as a card, a sidebar or a toolbar.
    case panel
    case window(id: UInt32)
    case screen
}

/// A rectangle (AppKit coordinates) the selection can snap to.
public struct SnapCandidate: Sendable, Equatable {
    public var rect: CGRect
    public var kind: SnapKind

    public init(rect: CGRect, kind: SnapKind) {
        self.rect = rect
        self.kind = kind
    }
}

/// Size rules for the snap rungs.
public enum SnapPolicy {
    /// Smaller elements are noise (a cursor, a dot).
    public static let minimumElement = CGSize(width: 24, height: 16)
    public static let minimumPanel = CGSize(width: 60, height: 40)
    /// A rung covering this share of its window is the window.
    public static let windowCollapse: CGFloat = 0.95
    /// Rects equal within this distance on every edge are one rung.
    public static let dedupeTolerance: CGFloat = 2
    /// The pointer must leave the current rung by this much before snapping changes.
    public static let hysteresis: CGFloat = 2
}

public enum SnapCandidateChain {
    /// The rungs inner → outer with the policy applied: too small ones dropped, every
    /// rung clamped to its window and screen, near-duplicates merged, the screen last.
    public static func make(
        element: CGRect?,
        block: CGRect?,
        panel: CGRect?,
        window: WindowInfo?,
        screen: CGRect,
        windowsOnly: Bool
    ) -> [SnapCandidate] {
        var chain: [SnapCandidate] = []
        let bounds = window.map { ScreenshotGeometry.clamp($0.frame, to: screen) } ?? screen
        let windowArea = bounds.width * bounds.height

        func add(_ rect: CGRect?, _ kind: SnapKind, minimum: CGSize?) {
            guard let rect else { return }
            let clamped = ScreenshotGeometry.clamp(rect, to: bounds)
            guard !clamped.isEmpty else { return }
            if let minimum, clamped.width < minimum.width || clamped.height < minimum.height { return }
            if window != nil, windowArea > 0, clamped.width * clamped.height >= SnapPolicy.windowCollapse * windowArea { return }
            if chain.contains(where: { nearlyEqual($0.rect, clamped) }) { return }
            chain.append(SnapCandidate(rect: clamped, kind: kind))
        }

        if !windowsOnly {
            add(element, .element, minimum: SnapPolicy.minimumElement)
            add(block, .block, minimum: nil)
            add(panel, .panel, minimum: SnapPolicy.minimumPanel)
        }
        if let window {
            let frame = ScreenshotGeometry.clamp(window.frame, to: screen)
            if !frame.isEmpty, !chain.contains(where: { nearlyEqual($0.rect, frame) }) {
                chain.append(SnapCandidate(rect: frame, kind: .window(id: window.id)))
            }
        }
        if !chain.contains(where: { nearlyEqual($0.rect, screen) }) {
            chain.append(SnapCandidate(rect: screen, kind: .screen))
        }
        return chain
    }

    /// `index` moved by `delta` rungs, wrapping around.
    public static func cycled(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }

    private static func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= SnapPolicy.dedupeTolerance
            && abs(a.minY - b.minY) <= SnapPolicy.dedupeTolerance
            && abs(a.maxX - b.maxX) <= SnapPolicy.dedupeTolerance
            && abs(a.maxY - b.maxY) <= SnapPolicy.dedupeTolerance
    }
}
