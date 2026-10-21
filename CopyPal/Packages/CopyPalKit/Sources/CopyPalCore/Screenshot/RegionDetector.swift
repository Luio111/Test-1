import Foundation

/// What the detector found on one screen: for every cell the element and the flat
/// region (panel) it belongs to, plus the text blocks elements form (M11).
public struct RegionMap: Sendable {
    public let width: Int
    public let height: Int
    public let cell: Int
    /// 0 = none, else index + 1 into `elementBoxes`.
    public let elementLabel: [Int32]
    /// 0 = none, else index + 1 into `panelBoxes`.
    public let panelLabel: [Int32]
    /// Element index → block index, or −1.
    public let blockOfElement: [Int32]
    /// In cells.
    public let elementBoxes: [PixelRect]
    public let blockBoxes: [PixelRect]
    public let panelBoxes: [PixelRect]
    /// Cells on an edge, where neither a flat region nor (necessarily) an element lies.
    public let isEdge: [Bool]

    /// The rungs at a cell: the element, its text block and the flat region around it,
    /// each cut to `window` (in cells) when given.
    public func rungs(atCell x: Int, _ y: Int, within window: PixelRect? = nil) -> (element: PixelRect?, block: PixelRect?, panel: PixelRect?) {
        guard x >= 0, y >= 0, x < width, y < height else { return (nil, nil, nil) }
        let index = y * width + x
        var element: PixelRect?
        var block: PixelRect?
        if elementLabel[index] > 0 {
            let elementIndex = Int(elementLabel[index]) - 1
            element = elementBoxes[elementIndex]
            let blockIndex = Int(blockOfElement[elementIndex])
            if blockIndex >= 0 { block = blockBoxes[blockIndex] }
        }
        var panel: PixelRect?
        if panelLabel[index] > 0 {
            panel = panelBoxes[Int(panelLabel[index]) - 1]
        } else {
            // On a border, a button's face or a line of text: the smallest flat region
            // whose box encloses the cell (a card with its border, a sidebar).
            for box in panelBoxes where box.contains(x, y) {
                if let current = panel, current.width * current.height <= box.width * box.height { continue }
                panel = box
            }
        }
        if let window {
            element = element.flatMap { $0.intersection(window) }
            block = block.flatMap { $0.intersection(window) }
            panel = panel.flatMap { $0.intersection(window) }
        }
        return (element, block, panel)
    }
}

/// Finds the things a screenshot can snap to from the frozen frame's brightness
/// alone: flat regions (cards, sidebars, toolbars), content components (buttons,
/// images, lines of text) and text blocks. Runs once per screen, off the main thread.
public enum RegionDetector {
    public struct Tuning: Sendable {
        /// Gradient from which a cell counts as an edge.
        public var gradientThreshold: UInt8 = 24
        /// Brightness difference up to which neighbours belong to one flat region.
        public var flatTolerance: Int = 12
        /// Closes the gaps between glyphs before components are formed.
        public var dilateRadius = 1
        /// Smallest flat region worth snapping to (cells; 40 × 24 pt at 2 pt cells).
        public var minimumPanelCells = (width: 20, height: 12)
        /// A flat region must fill this share of its bounding box (no L-shapes).
        public var minimumPanelFill: Float = 0.6
        public var minimumElementCells = (width: 4, height: 4)
        public var minimumComponentCells = 16
        /// Elements covering more of the screen are the screen's business.
        public var maximumElementShare: Float = 0.6
        /// An edge component enclosing a flat region of at least this share of its
        /// box is a frame around that region, not an element.
        public var frameMinimumPanelShare: Float = 0.5
        /// Lines in one text block differ in height by at most this factor.
        public var textHeightRatio: Float = 2
        /// Components at most this tall are lines of text (20 cells = 40 pt).
        public var textLineMaximumCells = 20
        /// Lines closer than this × the median line height belong to one block.
        public var textGapFactor: Float = 1.5
        /// Lines must overlap horizontally by this share of the narrower one.
        public var textOverlapMinimum: Float = 0.3
        /// A box grows by up to this many cells onto a surrounding border.
        public var refineMaximumCells = 2
        /// Share of a side's cells that must be edges to grow onto it.
        public var refineEdgeCoverage: Float = 0.6

        public init() {}
        public static let standard = Tuning()
    }

    public static func analyze(_ plane: LumaPlane, tuning: Tuning = .standard) -> RegionMap {
        let width = plane.width
        let height = plane.height
        let count = width * height
        guard count > 0 else {
            return RegionMap(width: width, height: height, cell: plane.cell, elementLabel: [], panelLabel: [], blockOfElement: [], elementBoxes: [], blockBoxes: [], panelBoxes: [], isEdge: [])
        }
        let gradient = plane.gradient()
        let edges = BitMask(width: width, height: height, bits: gradient.map { $0 >= tuning.gradientThreshold })

        // Flat regions: non-edge cells joined with neighbours of nearly the same brightness.
        var finder = UnionFind(count: count)
        for y in 0..<height {
            for x in 0..<width where !edges[x, y] {
                let index = y * width + x
                if x > 0, !edges[x - 1, y], abs(Int(plane[x, y]) - Int(plane[x - 1, y])) <= tuning.flatTolerance {
                    finder.union(index, index - 1)
                }
                if y > 0, !edges[x, y - 1], abs(Int(plane[x, y]) - Int(plane[x, y - 1])) <= tuning.flatTolerance {
                    finder.union(index, index - width)
                }
            }
        }
        let flat = finder.components(width: width, height: height, minCells: 1) { !edges.bits[$0] }
        var panelBoxes: [PixelRect] = []
        var panelRelabel = [Int32](repeating: 0, count: flat.boxes.count)
        for (index, box) in flat.boxes.enumerated() {
            let fill = Float(flat.areas[index]) / Float(box.width * box.height)
            guard box.width >= tuning.minimumPanelCells.width,
                  box.height >= tuning.minimumPanelCells.height,
                  fill >= tuning.minimumPanelFill else { continue }
            panelBoxes.append(refined(box, edges: edges, tuning: tuning))
            panelRelabel[index] = Int32(panelBoxes.count)
        }
        let panelLabel = flat.labels.map { $0 > 0 ? panelRelabel[Int($0) - 1] : 0 }

        // Elements: connected edge cells, gaps between glyphs closed. The boxes come
        // from the edge cells themselves, not from the halo the dilation adds.
        let dilated = edges.dilated(radius: tuning.dilateRadius)
        let components = dilated.components(minCells: tuning.minimumComponentCells)
        var tightBoxes = [PixelRect?](repeating: nil, count: components.boxes.count)
        for y in 0..<height {
            for x in 0..<width where edges[x, y] {
                let label = Int(components.labels[y * width + x])
                guard label > 0 else { continue }
                let cell = PixelRect(x: x, y: y, width: 1, height: 1)
                tightBoxes[label - 1] = tightBoxes[label - 1].map { $0.union(cell) } ?? cell
            }
        }
        var elementBoxes: [PixelRect] = []
        let maximumArea = Float(count) * tuning.maximumElementShare
        for box in tightBoxes.compactMap({ $0 }) {
            guard box.width >= tuning.minimumElementCells.width,
                  box.height >= tuning.minimumElementCells.height,
                  Float(box.area) <= maximumArea,
                  !isFrame(box, around: panelBoxes, tuning: tuning) else { continue }
            elementBoxes.append(refined(box, edges: edges, tuning: tuning))
        }
        // A pointer anywhere inside an element's box – on a button's flat face as much as
        // on its outline – belongs to it; the smallest box wins where boxes nest.
        var elementLabel = [Int32](repeating: 0, count: count)
        let byAreaDescending = elementBoxes.indices.sorted { elementBoxes[$0].width * elementBoxes[$0].height > elementBoxes[$1].width * elementBoxes[$1].height }
        for index in byAreaDescending {
            let box = elementBoxes[index]
            for y in box.y..<box.maxY {
                for x in box.x..<box.maxX {
                    elementLabel[y * width + x] = Int32(index + 1)
                }
            }
        }

        // Text blocks: lines of similar height, stacked closely, overlapping horizontally.
        let (blockBoxes, blockOfElement) = textBlocks(elementBoxes, tuning: tuning)

        return RegionMap(
            width: width,
            height: height,
            cell: plane.cell,
            elementLabel: elementLabel,
            panelLabel: panelLabel,
            blockOfElement: blockOfElement,
            elementBoxes: elementBoxes,
            blockBoxes: blockBoxes,
            panelBoxes: panelBoxes,
            isEdge: edges.bits
        )
    }

    /// An outline drawn around a flat region (a card's border, a text field's frame)
    /// is that region's business, not an element of its own: the panel already
    /// grows onto it. True when a panel fills most of `box`.
    private static func isFrame(_ box: PixelRect, around panels: [PixelRect], tuning: Tuning) -> Bool {
        for panel in panels {
            guard let overlap = panel.intersection(box) else { continue }
            if Float(overlap.area) >= 0.9 * Float(panel.area),
               Float(panel.area) >= tuning.frameMinimumPanelShare * Float(box.area) {
                return true
            }
        }
        return false
    }

    /// Grows `box` onto a surrounding border: one cell per side while most of the
    /// cells along the new side are edges.
    private static func refined(_ box: PixelRect, edges: BitMask, tuning: Tuning) -> PixelRect {
        var box = box
        func coverage(x xs: Range<Int>, y ys: Range<Int>) -> Float {
            var total = 0
            var hits = 0
            for y in ys where y >= 0 && y < edges.height {
                for x in xs where x >= 0 && x < edges.width {
                    total += 1
                    if edges[x, y] { hits += 1 }
                }
            }
            return total > 0 ? Float(hits) / Float(total) : 0
        }
        for _ in 0..<tuning.refineMaximumCells {
            var grew = false
            if box.y > 0, coverage(x: box.x..<box.maxX, y: (box.y - 1)..<box.y) >= tuning.refineEdgeCoverage {
                box.y -= 1
                box.height += 1
                grew = true
            }
            if box.maxY < edges.height, coverage(x: box.x..<box.maxX, y: box.maxY..<(box.maxY + 1)) >= tuning.refineEdgeCoverage {
                box.height += 1
                grew = true
            }
            if box.x > 0, coverage(x: (box.x - 1)..<box.x, y: box.y..<box.maxY) >= tuning.refineEdgeCoverage {
                box.x -= 1
                box.width += 1
                grew = true
            }
            if box.maxX < edges.width, coverage(x: box.maxX..<(box.maxX + 1), y: box.y..<box.maxY) >= tuning.refineEdgeCoverage {
                box.width += 1
                grew = true
            }
            if !grew { break }
        }
        return box
    }

    private static func textBlocks(_ elements: [PixelRect], tuning: Tuning) -> (boxes: [PixelRect], blockOfElement: [Int32]) {
        var blockOfElement = [Int32](repeating: -1, count: elements.count)
        let lines = elements.indices.filter { elements[$0].height <= tuning.textLineMaximumCells }
        guard lines.count >= 2 else { return ([], blockOfElement) }
        let heights = lines.map { elements[$0].height }.sorted()
        let median = Float(heights[heights.count / 2])
        let maximumGap = tuning.textGapFactor * median

        var finder = UnionFind(count: elements.count)
        for (position, a) in lines.enumerated() {
            for b in lines[(position + 1)...] {
                let boxA = elements[a], boxB = elements[b]
                // Stacked, not nested (a label on its button), of similar height.
                let gap = max(boxB.y - boxA.maxY, boxA.y - boxB.maxY)
                guard gap >= -1, Float(gap) < maximumGap else { continue }
                let heights = (Float(min(boxA.height, boxB.height)), Float(max(boxA.height, boxB.height)))
                guard heights.1 <= tuning.textHeightRatio * heights.0 else { continue }
                let overlap = min(boxA.maxX, boxB.maxX) - max(boxA.x, boxB.x)
                guard Float(overlap) >= tuning.textOverlapMinimum * Float(min(boxA.width, boxB.width)) else { continue }
                finder.union(a, b)
            }
        }
        var members: [Int: [Int]] = [:]
        for line in lines {
            members[finder.find(line), default: []].append(line)
        }
        var boxes: [PixelRect] = []
        for group in members.values.sorted(by: { $0[0] < $1[0] }) where group.count >= 2 {
            var box = elements[group[0]]
            for member in group.dropFirst() {
                box = box.union(elements[member])
            }
            for member in group {
                blockOfElement[member] = Int32(boxes.count)
            }
            boxes.append(box)
        }
        return (boxes, blockOfElement)
    }
}
