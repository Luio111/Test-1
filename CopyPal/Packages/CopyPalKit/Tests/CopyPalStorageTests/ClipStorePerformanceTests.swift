import CopyPalCore
import Foundation
import Testing
@testable import CopyPalStorage

/// ROADMAP M3: with 10,000 entries, reading the newest 8 takes < 5 ms and storing a
/// copy < 10 ms. Measured as the median of repeated runs, so one slow run on a busy
/// CI machine does not fail the build.
@Suite(.serialized)
struct ClipStorePerformanceTests {
    @Test func tenThousandEntries() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanUp() }
        for index in 0..<10_000 {
            try fixture.store.save(textClip("Eintrag Nummer \(index) mit etwas Text"))
        }
        #expect(try fixture.store.count() == 10_000)

        let clock = ContinuousClock()
        var reads: [Double] = []
        for _ in 0..<20 {
            let elapsed = try clock.measure { _ = try fixture.store.items(limit: 8) }
            reads.append(Self.milliseconds(elapsed))
        }
        var inserts: [Double] = []
        for index in 0..<20 {
            let elapsed = try clock.measure { try fixture.store.save(textClip("Neu \(index)")) }
            inserts.append(Self.milliseconds(elapsed))
        }
        let readMedian = LatencySummary(milliseconds: reads)!.median
        let insertMedian = LatencySummary(milliseconds: inserts)!.median
        print("ClipStore 10k: newest 8 median \(readMedian) ms, insert median \(insertMedian) ms")
        #expect(readMedian < 5)
        #expect(insertMedian < 10)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }
}
