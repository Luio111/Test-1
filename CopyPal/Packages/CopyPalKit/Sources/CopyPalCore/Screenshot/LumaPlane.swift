import Foundation

/// Brightness of a frame at a coarse grid, one value per cell of `cell` × `cell`
/// device pixels (2 pt), display-local with a top-left origin. The region detector
/// works on this instead of the full frame: a 5K display is 300 k cells.
public struct LumaPlane: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Device pixels per cell.
    public let cell: Int
    public var luma: [UInt8]

    public init(width: Int, height: Int, cell: Int, luma: [UInt8]) {
        precondition(luma.count == width * height, "LumaPlane: bad size")
        self.width = width
        self.height = height
        self.cell = cell
        self.luma = luma
    }

    /// Averages every cell of `buffer` (tests, fixtures; the app draws into a gray context).
    public init(buffer: PixelBuffer, cell: Int) {
        let cell = max(cell, 1)
        let width = (buffer.width + cell - 1) / cell
        let height = (buffer.height + cell - 1) / cell
        var luma = [UInt8](repeating: 0, count: width * height)
        for cy in 0..<height {
            for cx in 0..<width {
                var sum = 0
                var count = 0
                for y in (cy * cell)..<min((cy + 1) * cell, buffer.height) {
                    for x in (cx * cell)..<min((cx + 1) * cell, buffer.width) {
                        sum += buffer.luma(x: x, y: y)
                        count += 1
                    }
                }
                luma[cy * width + cx] = UInt8(clamping: count > 0 ? sum / count : 0)
            }
        }
        self.init(width: width, height: height, cell: cell, luma: luma)
    }

    @inlinable
    public subscript(x: Int, y: Int) -> UInt8 {
        luma[y * width + x]
    }

    /// |L(x+1) − L(x−1)| + |L(y+1) − L(y−1)| per cell, saturated; the frame's edge
    /// cells use their neighbour once.
    public func gradient() -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height)
        guard width > 0, height > 0 else { return result }
        for y in 0..<height {
            let up = max(y - 1, 0)
            let down = min(y + 1, height - 1)
            for x in 0..<width {
                let left = max(x - 1, 0)
                let right = min(x + 1, width - 1)
                let dx = abs(Int(self[right, y]) - Int(self[left, y]))
                let dy = abs(Int(self[x, down]) - Int(self[x, up]))
                result[y * width + x] = UInt8(clamping: dx + dy)
            }
        }
        return result
    }
}

/// A grid of flags the size of a `LumaPlane`.
public struct BitMask: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var bits: [Bool]

    public init(width: Int, height: Int, bits: [Bool]) {
        precondition(bits.count == width * height, "BitMask: bad size")
        self.width = width
        self.height = height
        self.bits = bits
    }

    public init(width: Int, height: Int, repeating value: Bool = false) {
        self.init(width: width, height: height, bits: [Bool](repeating: value, count: width * height))
    }

    @inlinable
    public subscript(x: Int, y: Int) -> Bool {
        get { bits[y * width + x] }
        set { bits[y * width + x] = newValue }
    }

    /// Every set cell also sets its neighbours within `radius` (separable max filter).
    public func dilated(radius: Int) -> BitMask {
        guard radius > 0, width > 0, height > 0 else { return self }
        var horizontal = BitMask(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                for dx in max(x - radius, 0)...min(x + radius, width - 1) {
                    horizontal[dx, y] = true
                }
            }
        }
        var result = BitMask(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where horizontal[x, y] {
                for dy in max(y - radius, 0)...min(y + radius, height - 1) {
                    result[x, dy] = true
                }
            }
        }
        return result
    }

    /// 4-connected components of the set cells, at least `minCells` large. `labels`
    /// holds the component index + 1 per cell (0: none, or too small).
    public func components(minCells: Int) -> (labels: [Int32], boxes: [PixelRect], areas: [Int]) {
        var finder = UnionFind(count: width * height)
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                let index = y * width + x
                if x > 0, self[x - 1, y] { finder.union(index, index - 1) }
                if y > 0, self[x, y - 1] { finder.union(index, index - width) }
            }
        }
        return finder.components(width: width, height: height, minCells: minCells) { self.bits[$0] }
    }
}

/// Union-find over grid cells, used for flat regions and edge components.
struct UnionFind {
    private var parent: [Int32]

    init(count: Int) {
        parent = (0..<count).map { Int32($0) }
    }

    mutating func find(_ index: Int) -> Int {
        var root = index
        while Int(parent[root]) != root { root = Int(parent[root]) }
        var current = index
        while Int(parent[current]) != root {
            let next = Int(parent[current])
            parent[current] = Int32(root)
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        if rootA != rootB { parent[max(rootA, rootB)] = Int32(min(rootA, rootB)) }
    }

    /// Components of the cells `included` returns true for, as labels (index + 1),
    /// bounding boxes and areas; components below `minCells` get label 0.
    mutating func components(width: Int, height: Int, minCells: Int, included: (Int) -> Bool) -> (labels: [Int32], boxes: [PixelRect], areas: [Int]) {
        var rootToIndex: [Int: Int] = [:]
        var boxes: [PixelRect] = []
        var areas: [Int] = []
        var rootOf = [Int32](repeating: -1, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard included(index) else { continue }
                let root = find(index)
                rootOf[index] = Int32(root)
                if let component = rootToIndex[root] {
                    var box = boxes[component]
                    let maxX = max(box.maxX, x + 1)
                    let maxY = max(box.maxY, y + 1)
                    box.x = min(box.x, x)
                    box.y = min(box.y, y)
                    box.width = maxX - box.x
                    box.height = maxY - box.y
                    boxes[component] = box
                    areas[component] += 1
                } else {
                    rootToIndex[root] = boxes.count
                    boxes.append(PixelRect(x: x, y: y, width: 1, height: 1))
                    areas.append(1)
                }
            }
        }
        // Keep the large components, renumbered densely.
        var kept: [Int32] = Array(repeating: 0, count: boxes.count)
        var keptBoxes: [PixelRect] = []
        var keptAreas: [Int] = []
        for (component, area) in areas.enumerated() where area >= minCells {
            keptBoxes.append(boxes[component])
            keptAreas.append(area)
            kept[component] = Int32(keptBoxes.count)
        }
        var labels = [Int32](repeating: 0, count: width * height)
        for index in labels.indices where rootOf[index] >= 0 {
            if let component = rootToIndex[Int(rootOf[index])] {
                labels[index] = kept[component]
            }
        }
        return (labels, keptBoxes, keptAreas)
    }
}
