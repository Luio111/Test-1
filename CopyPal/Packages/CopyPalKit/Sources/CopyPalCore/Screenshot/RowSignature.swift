import Foundation

/// One pixel row reduced to what the stitcher compares: an exact hash and a coarse
/// brightness profile for rows that differ only by sub-pixel scrolling (M11).
public struct RowSignature: Sendable, Hashable {
    /// FNV-1a over the row's bytes between the side insets.
    public var hash: UInt64
    /// Mean luma of `bandCount` horizontal bands, left to right.
    public var bands: [UInt8]

    public static let bandCount = 8

    public init(hash: UInt64, bands: [UInt8]) {
        self.hash = hash
        self.bands = bands
    }

    /// Sum of the band differences; small for the same content shifted by a fraction
    /// of a pixel, large for different content.
    public func bandDistance(to other: RowSignature) -> Int {
        var distance = 0
        for index in bands.indices {
            distance += abs(Int(bands[index]) - Int(other.bands[index]))
        }
        return distance
    }
}

public enum RowSignatures {
    /// Pixels at the left and right edge are left out: scrollbars fade in and out there.
    public static func sideInset(width: Int, scale: Int) -> Int {
        let inset = min(32 * scale, max(8 * scale, width / 25))
        return width > 4 * inset ? inset : 0
    }

    public static func signatures(of frame: PixelBuffer, inset: Int) -> [RowSignature] {
        (0..<frame.height).map { signature(of: frame, row: $0, inset: inset) }
    }

    public static func signature(of frame: PixelBuffer, row y: Int, inset: Int) -> RowSignature {
        let start = max(inset, 0)
        let end = max(frame.width - inset, start)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        var sums = [Int](repeating: 0, count: RowSignature.bandCount)
        var counts = [Int](repeating: 0, count: RowSignature.bandCount)
        let span = max(end - start, 1)
        var x = start
        while x < end {
            let i = frame.offset(x: x, y: y)
            // Alpha is constant for screen content and left out of the hash.
            for byte in [frame.bgra[i], frame.bgra[i + 1], frame.bgra[i + 2]] {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            let band = min((x - start) * RowSignature.bandCount / span, RowSignature.bandCount - 1)
            sums[band] += (Int(frame.bgra[i + 2]) * 77 + Int(frame.bgra[i + 1]) * 151 + Int(frame.bgra[i]) * 28) >> 8
            counts[band] += 1
            x += 1
        }
        let bands = (0..<RowSignature.bandCount).map { band in
            UInt8(clamping: counts[band] > 0 ? sums[band] / counts[band] : 0)
        }
        return RowSignature(hash: hash, bands: bands)
    }
}
