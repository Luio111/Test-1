#if os(macOS)
import AppKit
import CopyPalCore

/// Polls the pasteboard's change count (macOS has no change notification). Cheap:
/// one integer read every 0.4 s; types are read only after a change.
@MainActor
public final class PasteboardMonitor {
    public struct Change: Sendable, Equatable {
        public let changeCount: Int
        public let types: [String]
        /// `org.nspasteboard.source`, else the app in front when the change was noticed.
        public let sourceBundleID: String?
        /// CopyPal wrote this change itself.
        public let isOwnWrite: Bool
    }

    public var onChange: ((Change) -> Void)?
    public private(set) var isRunning = false
    public let pasteboard: NSPasteboard

    private let interval: TimeInterval
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ownChangeCounts: Set<Int> = []

    public init(pasteboard: NSPasteboard = .general, interval: TimeInterval = 0.4) {
        self.pasteboard = pasteboard
        self.interval = interval
        lastChangeCount = pasteboard.changeCount
    }

    /// Starts polling; what is on the pasteboard now is not reported.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Call right after CopyPal wrote the pasteboard.
    public func registerOwnWrite(changeCount: Int) {
        ownChangeCounts.insert(changeCount)
        if ownChangeCounts.count > 20 {
            ownChangeCounts.remove(ownChangeCounts.min() ?? changeCount)
        }
    }

    /// Checks right away instead of waiting for the next tick (tests, wake from sleep).
    public func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        let isOwn = ownChangeCounts.remove(changeCount) != nil
        let types = PasteboardReader.types(of: pasteboard)
        // The source marker is read only when present and the copy is not marked secret.
        let declared = types.contains(PasteboardTypeID.source) && PasteboardMarkers.decide(types: types) != .skip(.concealed)
            ? PasteboardReader.declaredSource(of: pasteboard)
            : nil
        onChange?(Change(
            changeCount: changeCount,
            types: types,
            sourceBundleID: declared ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            isOwnWrite: isOwn
        ))
    }
}
#endif
