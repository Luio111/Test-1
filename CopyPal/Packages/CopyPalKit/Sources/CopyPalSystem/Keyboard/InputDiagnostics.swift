#if os(macOS)
import Foundation
import CopyPalCore

/// One line in the lab's event log. Only key codes and modifiers, never characters;
/// and only events that involve the paste key or ⌘ are recorded.
public struct InputLogEntry: Sendable, Identifiable {
    public let id: Int
    public let uptime: TimeInterval
    public let kind: String
    public let keyCode: UInt16?
    public let modifiers: KeyModifiers
    public let isRepeat: Bool
    /// `eventSourceStateID` (1 = hardware) and source PID, to tell real from synthetic events.
    public let sourceState: Int64
    public let sourcePID: Int64
    public let decision: String
}

/// Thread-safe ring buffer and measurements shared between the tap thread and the UI.
public final class InputDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [InputLogEntry] = []
    private var nextID = 0
    private var tapDurations: [Double] = []
    private var popupLatencies: [Double] = []
    private var slowestCallback: Double = 0
    private var popupRequestedAt: UInt64?
    private let capacity: Int

    /// Recording is off unless the lab window is open.
    public var isRecording: Bool {
        get { lock.withLock { recording } }
        set { lock.withLock { recording = newValue } }
    }
    private var recording = false

    public init(capacity: Int = 40) {
        self.capacity = capacity
    }

    func log(
        kind: String,
        keyCode: UInt16? = nil,
        modifiers: KeyModifiers = [],
        isRepeat: Bool = false,
        sourceState: Int64 = 0,
        sourcePID: Int64 = 0,
        decision: String
    ) {
        lock.withLock {
            guard recording else { return }
            nextID += 1
            entries.append(InputLogEntry(
                id: nextID,
                uptime: ProcessInfo.processInfo.systemUptime,
                kind: kind,
                keyCode: keyCode,
                modifiers: modifiers,
                isRepeat: isRepeat,
                sourceState: sourceState,
                sourcePID: sourcePID,
                decision: decision
            ))
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }

    func recordTap(milliseconds: Double) {
        lock.withLock { tapDurations.append(milliseconds) }
    }

    func recordCallback(milliseconds: Double) {
        lock.withLock { slowestCallback = max(slowestCallback, milliseconds) }
    }

    func markPopupRequested() {
        lock.withLock { popupRequestedAt = DispatchTime.now().uptimeNanoseconds }
    }

    /// Call once the popup is on screen (from the main thread).
    public func markPopupVisible() {
        lock.withLock {
            guard let start = popupRequestedAt else { return }
            popupRequestedAt = nil
            popupLatencies.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
    }

    public struct Snapshot: Sendable {
        public var entries: [InputLogEntry]
        public var tap: LatencySummary?
        public var popup: LatencySummary?
        public var slowestCallback: Double

        public static let empty = Snapshot(entries: [], tap: nil, popup: nil, slowestCallback: 0)
    }

    public func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                entries: entries,
                tap: LatencySummary(milliseconds: tapDurations),
                popup: LatencySummary(milliseconds: popupLatencies),
                slowestCallback: slowestCallback
            )
        }
    }

    public func reset() {
        lock.withLock {
            entries.removeAll()
            tapDurations.removeAll()
            popupLatencies.removeAll()
            slowestCallback = 0
        }
    }
}
#endif
