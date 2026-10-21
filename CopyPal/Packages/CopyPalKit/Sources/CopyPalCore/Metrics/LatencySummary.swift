/// Median, 90th percentile and maximum of a series of durations in milliseconds.
public struct LatencySummary: Sendable, Equatable {
    public var count: Int
    public var median: Double
    public var p90: Double
    public var max: Double

    public init?(milliseconds values: [Double]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        count = sorted.count
        median = sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
        // Nearest-rank percentile.
        let rank = Int((0.9 * Double(sorted.count)).rounded(.up))
        p90 = sorted[Swift.max(rank, 1) - 1]
        max = sorted[sorted.count - 1]
    }
}
