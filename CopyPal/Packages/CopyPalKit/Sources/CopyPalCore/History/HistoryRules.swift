import Foundation

/// Limits for the history (ROADMAP D6). Favorites are exempt from all of them.
public struct RetentionPolicy: Sendable, Equatable {
    public var maxItems: Int
    /// Entries not used for this long are removed; nil keeps them forever.
    public var maxAge: TimeInterval?
    /// Sensitive entries are removed this long after they were copied.
    public var sensitiveLifetime: TimeInterval
    public var maxTotalBytes: Int
    public var maxTextBytes: Int
    public var maxImageBytes: Int

    public init(
        maxItems: Int = 500,
        maxAge: TimeInterval? = 30 * 86_400,
        sensitiveLifetime: TimeInterval = 60,
        maxTotalBytes: Int = 1_000_000_000,
        maxTextBytes: Int = 2_000_000,
        maxImageBytes: Int = 25_000_000
    ) {
        self.maxItems = maxItems
        self.maxAge = maxAge
        self.sensitiveLifetime = sensitiveLifetime
        self.maxTotalBytes = maxTotalBytes
        self.maxTextBytes = maxTextBytes
        self.maxImageBytes = maxImageBytes
    }

    public static let standard = RetentionPolicy()
}

/// The metadata the retention rules need about an entry.
public struct RetentionCandidate: Sendable, Equatable {
    public var id: UUID
    public var lastUsedAt: Date
    public var isPinned: Bool
    public var expiresAt: Date?
    public var byteSize: Int

    public init(id: UUID, lastUsedAt: Date, isPinned: Bool = false, expiresAt: Date? = nil, byteSize: Int = 0) {
        self.id = id
        self.lastUsedAt = lastUsedAt
        self.isPinned = isPinned
        self.expiresAt = expiresAt
        self.byteSize = byteSize
    }
}

public enum HistoryRules {
    /// Entries to delete: expired, unused for longer than `maxAge`, beyond `maxItems`,
    /// and the oldest ones while the total exceeds `maxTotalBytes`. Favorites are kept
    /// and count towards neither limit.
    public static func itemsToRemove(_ items: [RetentionCandidate], policy: RetentionPolicy, now: Date) -> [UUID] {
        var removed: Set<UUID> = []
        var kept: [RetentionCandidate] = []
        for item in items where !item.isPinned {
            if let expiresAt = item.expiresAt, expiresAt <= now {
                removed.insert(item.id)
            } else if let maxAge = policy.maxAge, now.timeIntervalSince(item.lastUsedAt) > maxAge {
                removed.insert(item.id)
            } else {
                kept.append(item)
            }
        }

        // Newest first; everything after the limit goes. Favorites do not count.
        kept.sort { $0.lastUsedAt > $1.lastUsedAt }
        let allowed = max(policy.maxItems, 0)
        if kept.count > allowed {
            removed.formUnion(kept[allowed...].map(\.id))
            kept.removeSubrange(allowed...)
        }

        var total = kept.reduce(0) { $0 + $1.byteSize }
        while total > policy.maxTotalBytes, let oldest = kept.popLast() {
            removed.insert(oldest.id)
            total -= oldest.byteSize
        }
        return items.map(\.id).filter(removed.contains)
    }

    /// Whether a copy of this size is stored at all.
    public static func accepts(kind: ClipKind, byteSize: Int, policy: RetentionPolicy) -> Bool {
        switch kind {
        case .image: byteSize <= policy.maxImageBytes
        case .files: true // stored as references only
        case .text, .richText, .link, .color, .other: byteSize <= policy.maxTextBytes
        }
    }

    public static func expiry(for sensitivity: Sensitivity?, policy: RetentionPolicy, now: Date) -> Date? {
        sensitivity == nil ? nil : now.addingTimeInterval(policy.sensitiveLifetime)
    }
}
