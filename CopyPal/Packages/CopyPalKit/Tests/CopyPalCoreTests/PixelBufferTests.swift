import Testing
@testable import CopyPalCore

struct PixelBufferTests {
    @Test func blackBufferIsOpaque() {
        let buffer = PixelBuffer(width: 3, height: 2)
        #expect(buffer.bgra.count == 24)
        #expect(buffer.luma(x: 2, y: 1) == 0)
        #expect(buffer.bgra[3] == 255)
        #expect(buffer.row(1).count == 12)
    }

    @Test func lumaWeightsGreenMost() {
        var buffer = PixelBuffer(width: 3, height: 1)
        buffer.fill(PixelRect(x: 0, y: 0, width: 1, height: 1), b: 0, g: 0, r: 255)
        buffer.fill(PixelRect(x: 1, y: 0, width: 1, height: 1), b: 0, g: 255, r: 0)
        buffer.fill(PixelRect(x: 2, y: 0, width: 1, height: 1), b: 255, g: 0, r: 0)
        let lumas = buffer.lumaRow(0)
        #expect(lumas[1] > lumas[0])
        #expect(lumas[0] > lumas[2])
        #expect(lumas.allSatisfy { (0...255).contains($0) })
        var white = PixelBuffer(width: 1, height: 1)
        white.fill(PixelRect(x: 0, y: 0, width: 1, height: 1), b: 255, g: 255, r: 255)
        #expect(white.luma(x: 0, y: 0) == 255)
    }

    @Test func croppingClampsToTheBuffer() {
        var buffer = PixelBuffer(width: 4, height: 4)
        buffer.fill(PixelRect(x: 2, y: 2, width: 2, height: 2), b: 10, g: 20, r: 30)
        let cropped = buffer.cropped(PixelRect(x: 2, y: 2, width: 10, height: 10))
        #expect(cropped.width == 2 && cropped.height == 2)
        #expect(cropped.bgra[0] == 10 && cropped.bgra[1] == 20 && cropped.bgra[2] == 30)
        #expect(buffer.cropped(PixelRect(x: 5, y: 5, width: 1, height: 1)).isEmpty)
    }

    @Test func stackingAppendsRows() {
        var top = PixelBuffer(width: 2, height: 1)
        top.fill(PixelRect(x: 0, y: 0, width: 2, height: 1), b: 1, g: 1, r: 1)
        let bottom = PixelBuffer(width: 2, height: 2)
        let stacked = PixelBuffer.stacked([top, bottom])
        #expect(stacked.width == 2 && stacked.height == 3)
        #expect(stacked.luma(x: 0, y: 0) == 1)
        #expect(stacked.luma(x: 1, y: 2) == 0)
        #expect(PixelBuffer.stacked([]).isEmpty)
    }

    @Test func paddedRowsAreHonored() {
        // 2 visible pixels per row, 12 bytes per row (one pixel of padding).
        var bytes = [UInt8](repeating: 0, count: 24)
        bytes[12] = 7 // blue of (0, 1)
        let buffer = PixelBuffer(width: 2, height: 2, bytesPerRow: 12, bgra: bytes)
        #expect(buffer.row(1).count == 8)
        #expect(buffer.row(1).first == 7)
        #expect(buffer.cropped(PixelRect(x: 0, y: 1, width: 2, height: 1)).bgra.first == 7)
    }
}
