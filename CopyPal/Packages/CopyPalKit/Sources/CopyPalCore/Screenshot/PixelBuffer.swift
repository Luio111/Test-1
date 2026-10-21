import Foundation

/// Raw pixels of a captured frame, 8-bit BGRA (premultiplied), rows top to bottom: the
/// form the stitcher and the region detector work on, without CoreGraphics (M11).
public struct PixelBuffer: Sendable, Equatable {
    public static let bytesPerPixel = 4

    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public var bgra: [UInt8]

    public init(width: Int, height: Int, bytesPerRow: Int? = nil, bgra: [UInt8]) {
        let bytesPerRow = bytesPerRow ?? width * Self.bytesPerPixel
        precondition(width >= 0 && height >= 0 && bytesPerRow >= width * Self.bytesPerPixel, "PixelBuffer: bad geometry")
        precondition(bgra.count >= bytesPerRow * height, "PixelBuffer: too few bytes")
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.bgra = bgra
    }

    /// A black, opaque buffer.
    public init(width: Int, height: Int) {
        var bytes = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)
        var index = 3
        while index < bytes.count {
            bytes[index] = 255
            index += Self.bytesPerPixel
        }
        self.init(width: width, height: height, bgra: bytes)
    }

    public var isEmpty: Bool { width == 0 || height == 0 }

    @inlinable
    public func offset(x: Int, y: Int) -> Int {
        y * bytesPerRow + x * Self.bytesPerPixel
    }

    /// Luma 0…255 (Rec. 601 weights, integer arithmetic).
    @inlinable
    public func luma(x: Int, y: Int) -> Int {
        let i = offset(x: x, y: y)
        return (Int(bgra[i + 2]) * 77 + Int(bgra[i + 1]) * 151 + Int(bgra[i]) * 28) >> 8
    }

    /// The bytes of row `y`, without the padding beyond `width`.
    public func row(_ y: Int) -> ArraySlice<UInt8> {
        let start = y * bytesPerRow
        return bgra[start..<(start + width * Self.bytesPerPixel)]
    }

    /// Luma of every pixel in row `y`, left to right.
    public func lumaRow(_ y: Int) -> [Int] {
        (0..<width).map { luma(x: $0, y: y) }
    }

    /// The pixels inside `rect` (clamped to the buffer) as a tightly packed buffer.
    public func cropped(_ rect: PixelRect) -> PixelBuffer {
        let x0 = max(rect.x, 0), y0 = max(rect.y, 0)
        let x1 = min(rect.maxX, width), y1 = min(rect.maxY, height)
        guard x1 > x0, y1 > y0 else { return PixelBuffer(width: 0, height: 0, bgra: []) }
        let newWidth = x1 - x0, newHeight = y1 - y0
        var bytes = [UInt8]()
        bytes.reserveCapacity(newWidth * newHeight * Self.bytesPerPixel)
        for y in y0..<y1 {
            let start = offset(x: x0, y: y)
            bytes.append(contentsOf: bgra[start..<(start + newWidth * Self.bytesPerPixel)])
        }
        return PixelBuffer(width: newWidth, height: newHeight, bgra: bytes)
    }

    /// `parts` stacked top to bottom; they must share one width.
    public static func stacked(_ parts: [PixelBuffer]) -> PixelBuffer {
        guard let first = parts.first else { return PixelBuffer(width: 0, height: 0, bgra: []) }
        let width = first.width
        var bytes = [UInt8]()
        var height = 0
        bytes.reserveCapacity(parts.reduce(0) { $0 + $1.height } * width * Self.bytesPerPixel)
        for part in parts {
            precondition(part.width == width, "PixelBuffer.stacked: widths differ")
            for y in 0..<part.height {
                bytes.append(contentsOf: part.row(y))
            }
            height += part.height
        }
        return PixelBuffer(width: width, height: height, bgra: bytes)
    }

    /// Fills `rect` with one color (tests and fixtures).
    public mutating func fill(_ rect: PixelRect, b: UInt8, g: UInt8, r: UInt8, a: UInt8 = 255) {
        let x0 = max(rect.x, 0), y0 = max(rect.y, 0)
        let x1 = min(rect.maxX, width), y1 = min(rect.maxY, height)
        guard x1 > x0, y1 > y0 else { return }
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = offset(x: x, y: y)
                bgra[i] = b
                bgra[i + 1] = g
                bgra[i + 2] = r
                bgra[i + 3] = a
            }
        }
    }
}
