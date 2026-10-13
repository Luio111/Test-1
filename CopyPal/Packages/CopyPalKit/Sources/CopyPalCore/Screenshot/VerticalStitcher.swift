import Foundation

/// How the stitcher decides (tunable, with the values that work for screen content).
public struct StitchSettings: Sendable, Equatable {
    /// Rows that must overlap between two frames; smaller overlaps are guesswork.
    public var minimumOverlapRows: Int
    /// Rows with information (not the background) that must agree for a match.
    public var minimumInformativeMatches: Int
    /// Share of the informative rows in the overlap that must agree. Two offsets that
    /// both reach it (repeated content) make the frame ambiguous.
    public var minimumScore: Double
    /// Band distance up to which two rows count as the same (sub-pixel scrolling).
    public var bandTolerance: Int
    /// A row hash that occurs more often than this is background and carries no information.
    public var maximumRowRepeats: Int
    /// Total height after which the capture stops.
    public var maximumHeight: Int

    public init(
        minimumOverlapRows: Int = 24,
        minimumInformativeMatches: Int = 12,
        minimumScore: Double = 0.85,
        bandTolerance: Int = 24,
        maximumRowRepeats: Int = 2,
        maximumHeight: Int = 20_000
    ) {
        self.minimumOverlapRows = minimumOverlapRows
        self.minimumInformativeMatches = minimumInformativeMatches
        self.minimumScore = minimumScore
        self.bandTolerance = bandTolerance
        self.maximumRowRepeats = maximumRowRepeats
        self.maximumHeight = maximumHeight
    }

    public static let standard = StitchSettings()
}

public enum ScrollDirection: Sendable, Equatable {
    /// Content moves up, new rows appear at the bottom (↓).
    case down
    /// Content moves down, new rows appear at the top (↑).
    case up
}

/// Joins the frames of a scrolling capture into one tall image (ROADMAP M11).
///
/// Every frame is compared with the previous one by row: the offset that makes the
/// informative rows agree is the scroll distance, rows that stayed in place while the
/// content moved are a fixed header or footer and are left out, and the rows beyond
/// the overlap are the new section. An offset that is not clearly better than the
/// runner-up (repeated content) is refused rather than guessed. Frames of one session
/// must share a width and a direction.
public struct VerticalStitcher: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// `rows` new rows were added.
        case appended(rows: Int)
        /// The frame shows the same content as before: nothing scrolled, or the end.
        case unchanged
        /// Several offsets fit equally well; the frame is dropped.
        case ambiguous
        /// Nothing in the frame matches the previous one (scrolled too far or changed).
        case noOverlap
        /// The capture is as tall as it may get; the frame is dropped.
        case reachedLimit
        /// The session scrolls the other way; the frame is dropped.
        case wrongDirection
    }

    public let settings: StitchSettings
    public private(set) var direction: ScrollDirection?
    /// Static rows at the top and bottom of the viewport (fixed header, footer), as
    /// seen in the latest accepted pair of frames.
    public private(set) var header = 0
    public private(set) var footer = 0
    /// Whether the latest accepted match agreed on the exact hashes (false: bands).
    public private(set) var lastMatchWasExact = true

    private let inset: Int
    private let firstFrame: PixelBuffer
    private var lastFrame: PixelBuffer
    private var lastSignatures: [RowSignature]
    /// The new rows of every accepted frame, oldest first (for ↓ below, for ↑ above).
    private var sections: [PixelBuffer] = []
    /// What `lastFrame` and the static bands were before each accepted frame (undo).
    private var history: [(frame: PixelBuffer, header: Int, footer: Int, exact: Bool)] = []
    /// The footer (↓) or header (↑) of the first pair, cut from the first frame.
    private var firstStaticBand = 0

    public init(firstFrame: PixelBuffer, scale: Int = 2, settings: StitchSettings = .standard) {
        self.settings = settings
        self.firstFrame = firstFrame
        lastFrame = firstFrame
        inset = RowSignatures.sideInset(width: firstFrame.width, scale: scale)
        lastSignatures = RowSignatures.signatures(of: firstFrame, inset: inset)
    }

    public var sectionCount: Int { sections.count }

    /// Height of the result so far.
    public var height: Int {
        guard let direction else { return firstFrame.height }
        let staticBand = direction == .down ? footer : header
        return firstFrame.height - firstStaticBand + sections.reduce(0) { $0 + $1.height } + staticBand
    }

    /// The viewport as the stitcher last saw it.
    public var latestFrame: PixelBuffer { lastFrame }

    // MARK: Frames

    public mutating func append(_ frame: PixelBuffer, direction wanted: ScrollDirection) -> Outcome {
        guard frame.width == firstFrame.width, frame.height == firstFrame.height else { return .noOverlap }
        if let direction, direction != wanted { return .wrongDirection }
        if height >= settings.maximumHeight { return .reachedLimit }

        let signatures = RowSignatures.signatures(of: frame, inset: inset)
        let analysis = Self.analyze(signatures, maximumRepeats: settings.maximumRowRepeats)
        guard let match = bestShift(next: signatures, nextInformative: analysis.informative, direction: wanted) else {
            if Self.identical(signatures, lastSignatures) { return .unchanged }
            return .noOverlap
        }
        switch match {
        case .ambiguous: return .ambiguous
        case .none: return .unchanged
        case let .shift(shift, exact):
            let height = frame.height
            let staticRows = Self.staticRows(
                previous: lastSignatures,
                next: signatures,
                shift: shift,
                tolerance: exact ? 0 : settings.bandTolerance,
                background: analysis.background,
                cap: height / 3
            )
            let newHeader = staticRows.header
            let newFooter = staticRows.footer
            // The previous frame's last visible content row (above its footer) now sits
            // `shift` rows higher; everything below it, down to the footer, is new.
            let section: PixelBuffer
            if shift > 0 {
                let start = max(height - shift - newFooter, newHeader)
                let end = height - newFooter
                guard end > start else { return .unchanged }
                section = frame.cropped(PixelRect(x: 0, y: start, width: frame.width, height: end - start))
            } else {
                let start = newHeader
                let end = min(newHeader - shift, height - newFooter)
                guard end > start else { return .unchanged }
                section = frame.cropped(PixelRect(x: 0, y: start, width: frame.width, height: end - start))
            }
            if direction == nil {
                direction = wanted
                firstStaticBand = wanted == .down ? newFooter : newHeader
            }
            history.append((lastFrame, header, footer, lastMatchWasExact))
            sections.append(section)
            header = newHeader
            footer = newFooter
            lastMatchWasExact = exact
            lastFrame = frame
            lastSignatures = signatures
            return .appended(rows: section.height)
        }
    }

    /// Drops the latest section; the next frame is matched against the frame before it.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast(), !sections.isEmpty else { return false }
        sections.removeLast()
        lastFrame = previous.frame
        header = previous.header
        footer = previous.footer
        lastMatchWasExact = previous.exact
        lastSignatures = RowSignatures.signatures(of: lastFrame, inset: inset)
        if sections.isEmpty {
            direction = nil
            firstStaticBand = 0
        }
        return true
    }

    /// The stitched image: the first frame without its static band, the sections, and
    /// the static band once at the far end. Without sections, the first frame.
    public func composite() -> PixelBuffer {
        guard let direction, !sections.isEmpty else { return firstFrame }
        let width = firstFrame.width
        let height = firstFrame.height
        switch direction {
        case .down:
            var parts = [firstFrame.cropped(PixelRect(x: 0, y: 0, width: width, height: height - firstStaticBand))]
            parts.append(contentsOf: sections)
            if footer > 0 {
                parts.append(lastFrame.cropped(PixelRect(x: 0, y: height - footer, width: width, height: footer)))
            }
            return PixelBuffer.stacked(parts)
        case .up:
            var parts: [PixelBuffer] = []
            if header > 0 {
                parts.append(lastFrame.cropped(PixelRect(x: 0, y: 0, width: width, height: header)))
            }
            parts.append(contentsOf: sections.reversed())
            parts.append(firstFrame.cropped(PixelRect(x: 0, y: firstStaticBand, width: width, height: height - firstStaticBand)))
            return PixelBuffer.stacked(parts)
        }
    }

    // MARK: Matching

    private enum Match: Equatable {
        case shift(Int, exact: Bool)
        case none
        case ambiguous
    }

    /// The offset by which the content moved between `lastSignatures` and `next`:
    /// positive when it moved up (scrolled down). Exact hashes first, bands second.
    private func bestShift(next: [RowSignature], nextInformative: [Bool], direction: ScrollDirection) -> Match? {
        if let exact = bestShift(next: next, nextInformative: nextInformative, direction: direction, tolerance: 0) {
            if case .shift = exact { return exact }
            if exact == .ambiguous { return exact }
        }
        if let tolerant = bestShift(next: next, nextInformative: nextInformative, direction: direction, tolerance: settings.bandTolerance) {
            return tolerant
        }
        return nil
    }

    private func bestShift(next: [RowSignature], nextInformative: [Bool], direction: ScrollDirection, tolerance: Int) -> Match? {
        let previous = lastSignatures
        let height = next.count
        guard height == previous.count, height > settings.minimumOverlapRows else { return nil }
        let same: (RowSignature, RowSignature) -> Bool = tolerance == 0
            ? { $0.hash == $1.hash }
            : { $0.hash == $1.hash || $0.bandDistance(to: $1) <= tolerance }

        // No movement: the informative rows agree at the same index.
        let unchanged = Self.score(previous: previous, next: next, nextInformative: nextInformative, shift: 0, same: same)
        if unchanged.total >= settings.minimumInformativeMatches, Double(unchanged.matches) >= settings.minimumScore * Double(unchanged.total) {
            return Match.none
        }

        // Every offset at which the informative rows agree is a candidate. One candidate
        // (give or take a few rows of drift) is a match; two are repeated content.
        var best: (shift: Int, matches: Int)?
        var otherCandidate = false
        let range = direction == .down ? (1...(height - settings.minimumOverlapRows)) : ((-(height - settings.minimumOverlapRows))...(-1))
        for shift in range {
            let result = Self.score(previous: previous, next: next, nextInformative: nextInformative, shift: shift, same: same)
            guard result.matches >= settings.minimumInformativeMatches,
                  Double(result.matches) >= settings.minimumScore * Double(result.total) else {
                continue
            }
            if let current = best {
                if abs(shift - current.shift) > 3 { otherCandidate = true }
                if result.matches > current.matches { best = (shift, result.matches) }
            } else {
                best = (shift, result.matches)
            }
        }
        guard let best else { return nil }
        return otherCandidate ? .ambiguous : .shift(best.shift, exact: tolerance == 0)
    }

    /// How many informative rows of `next` agree with `previous` moved by `shift`.
    private static func score(
        previous: [RowSignature],
        next: [RowSignature],
        nextInformative: [Bool],
        shift: Int,
        same: (RowSignature, RowSignature) -> Bool
    ) -> (matches: Int, total: Int) {
        let height = next.count
        let start = max(0, -shift)
        let end = min(height, height - shift)
        var matches = 0
        var total = 0
        var row = start
        while row < end {
            // Rows that look the same at the same index (fixed header, footer) say
            // nothing about a movement and are left out, except when testing for none.
            if nextInformative[row], shift == 0 || next[row].hash != previous[row].hash {
                total += 1
                if same(next[row], previous[row + shift]) { matches += 1 }
            }
            row += 1
        }
        return (matches, total)
    }

    /// Rows that stayed in place although the content moved by `shift`: a fixed header
    /// (run at the top) and footer (run at the bottom), each at most `cap` rows. Rows of
    /// the background (blank lines) decide nothing: they only bridge a run, so a white
    /// line inside a toolbar does not split it and a blank line next to a footer does
    /// not join it.
    private static func staticRows(
        previous: [RowSignature],
        next: [RowSignature],
        shift: Int,
        tolerance: Int,
        background: UInt64?,
        cap: Int
    ) -> (header: Int, footer: Int) {
        let height = next.count
        func unchangedInPlace(_ row: Int) -> Bool {
            guard next[row].hash == previous[row].hash else { return false }
            let moved = row + shift
            guard moved >= 0, moved < height else { return true }
            let same = next[row].hash == previous[moved].hash || (tolerance > 0 && next[row].bandDistance(to: previous[moved]) <= tolerance)
            return !same
        }
        func run(_ rows: some Sequence<Int>) -> Int {
            var length = 0
            var confirmed = 0
            for row in rows {
                guard length < cap, unchangedInPlace(row) else { break }
                length += 1
                if next[row].hash != background { confirmed = length }
            }
            return confirmed
        }
        let header = run(0..<height)
        let footer = run(stride(from: height - 1, through: header, by: -1))
        return (header, footer)
    }

    /// Which rows carry information (a rare hash; repeated rows are background or
    /// rulings) and which hash is the background, if any row repeats often enough.
    private static func analyze(_ signatures: [RowSignature], maximumRepeats: Int) -> (informative: [Bool], background: UInt64?) {
        var counts: [UInt64: Int] = [:]
        for signature in signatures {
            counts[signature.hash, default: 0] += 1
        }
        let background = counts.max { $0.value < $1.value }.flatMap { $0.value > maximumRepeats ? $0.key : nil }
        return (signatures.map { counts[$0.hash, default: 0] <= maximumRepeats }, background)
    }

    private static func identical(_ a: [RowSignature], _ b: [RowSignature]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.hash == $1.hash }
    }
}
