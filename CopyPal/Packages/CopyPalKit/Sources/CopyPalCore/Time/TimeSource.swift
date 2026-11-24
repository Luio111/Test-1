import Foundation

/// The current time, injectable for tests and for the debug "time + N days" switch.
public protocol TimeSource: Sendable {
    func now() -> Date
}

public struct SystemTimeSource: TimeSource {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// System time plus an adjustable offset (debug builds, tests).
public final class OffsetTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOffset: TimeInterval
    private let base: @Sendable () -> Date

    public init(offset: TimeInterval = 0, base: @escaping @Sendable () -> Date = { Date() }) {
        storedOffset = offset
        self.base = base
    }

    public var offset: TimeInterval {
        get { lock.withLock { storedOffset } }
        set { lock.withLock { storedOffset = newValue } }
    }

    public func advance(by interval: TimeInterval) {
        lock.withLock { storedOffset += interval }
    }

    public func now() -> Date {
        base().addingTimeInterval(offset)
    }
}
