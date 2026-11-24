import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What the pointer does in the markup editor (ROADMAP R33). Every tool has a letter.
public enum AnnotationTool: String, CaseIterable, Codable, Sendable {
    case select
    case pen
    case highlighter
    case arrow
    case line
    case rectangle
    case ellipse
    case text

    /// The letter that picks the tool, matched by character (any keyboard layout).
    public var key: Character {
        switch self {
        case .select: "v"
        case .pen: "p"
        case .highlighter: "h"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .text: "t"
        }
    }

    public static func tool(forKey character: Character) -> AnnotationTool? {
        let lowered = Character(character.lowercased())
        return allCases.first { $0.key == lowered }
    }

    /// Text is sized by its font, everything else by its line.
    public var usesFontSize: Bool {
        self == .text
    }

    public var canFill: Bool {
        self == .rectangle || self == .ellipse
    }
}

/// A colour of the markup, sRGB components from 0 to 1.
public struct AnnotationColor: Codable, Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    public static let red = AnnotationColor(hex: 0xFF3B30)
    public static let orange = AnnotationColor(hex: 0xFF9500)
    public static let yellow = AnnotationColor(hex: 0xFFCC00)
    public static let green = AnnotationColor(hex: 0x34C759)
    public static let blue = AnnotationColor(hex: 0x007AFF)
    public static let purple = AnnotationColor(hex: 0xAF52DE)
    public static let black = AnnotationColor(hex: 0x000000)
    public static let white = AnnotationColor(hex: 0xFFFFFF)

    /// The swatches of the editor; any other colour comes from the colour panel.
    public static let palette: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    /// Relative luminance (WCAG 2).
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The text colour on a bubble of this colour: white on red, blue and purple (as
    /// on Apple's own badges), black on yellow, green, orange and white.
    public var textColorOnTop: AnnotationColor {
        luminance > 0.4 ? .black : .white
    }
}

/// How an annotation looks. Sizes are in points of the picture, so a 20 pt text is as
/// large as 20 pt text on the screen it was taken from.
public struct AnnotationStyle: Codable, Sendable, Hashable {
    public var color: AnnotationColor
    public var lineWidth: Double
    public var fontSize: Double
    /// Rectangle and ellipse: filled with the colour instead of outlined.
    public var filled: Bool
    /// Text: on a rounded bubble in the colour, the text in white or black on it.
    public var textBackground: Bool

    public init(color: AnnotationColor, lineWidth: Double, fontSize: Double = 20, filled: Bool = false, textBackground: Bool = true) {
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.filled = filled
        self.textBackground = textBackground
    }

    public static let lineWidthRange: ClosedRange<Double> = 1...24
    public static let highlighterWidthRange: ClosedRange<Double> = 6...60
    public static let fontSizeRange: ClosedRange<Double> = 8...96

    public static func defaults(for tool: AnnotationTool) -> AnnotationStyle {
        switch tool {
        case .select, .arrow:
            AnnotationStyle(color: .red, lineWidth: 5)
        case .pen, .line, .rectangle, .ellipse:
            AnnotationStyle(color: .red, lineWidth: 4)
        case .highlighter:
            AnnotationStyle(color: .yellow, lineWidth: 22)
        case .text:
            AnnotationStyle(color: .red, lineWidth: 4, fontSize: 20, textBackground: true)
        }
    }

    public static func widthRange(for tool: AnnotationTool) -> ClosedRange<Double> {
        tool == .highlighter ? highlighterWidthRange : lineWidthRange
    }

    /// Steps of the size keys ([ and ]) and the editor's slider.
    public static func sizeStep(for tool: AnnotationTool) -> Double {
        switch tool {
        case .text: 2
        case .highlighter: 4
        default: 1
        }
    }

    /// Sizes inside what the editor offers for `tool`, whole points.
    public func clamped(for tool: AnnotationTool) -> AnnotationStyle {
        var style = self
        let widths = Self.widthRange(for: tool)
        style.lineWidth = min(max(lineWidth.rounded(), widths.lowerBound), widths.upperBound)
        style.fontSize = min(max(fontSize.rounded(), Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        return style
    }
}

/// The last style of every tool, kept between screenshots (settings, as JSON).
public struct AnnotationStyleBook: Codable, Sendable, Equatable {
    private var styles: [String: AnnotationStyle] = [:]

    public init() {}

    public subscript(tool: AnnotationTool) -> AnnotationStyle {
        get {
            (styles[tool.rawValue] ?? AnnotationStyle.defaults(for: tool)).clamped(for: tool)
        }
        set {
            styles[tool.rawValue] = newValue.clamped(for: tool)
        }
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Unknown or damaged data gives the defaults.
    public static func decoded(_ data: Data?) -> AnnotationStyleBook {
        guard let data, let book = try? JSONDecoder().decode(AnnotationStyleBook.self, from: data) else {
            return AnnotationStyleBook()
        }
        return book
    }
}

/// The geometry of an annotation in points of the picture, origin top left, y down.
public enum AnnotationShape: Sendable, Equatable {
    case pen([CGPoint])
    case highlighter([CGPoint])
    case line(from: CGPoint, to: CGPoint)
    case arrow(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    /// `at` is the top-left corner of the text's box (bubble or not).
    case text(String, at: CGPoint)

    public var tool: AnnotationTool {
        switch self {
        case .pen: .pen
        case .highlighter: .highlighter
        case .line: .line
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        }
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> AnnotationShape {
        func move(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + dx, y: point.y + dy)
        }
        switch self {
        case let .pen(points): return .pen(points.map(move))
        case let .highlighter(points): return .highlighter(points.map(move))
        case let .line(start, end): return .line(from: move(start), to: move(end))
        case let .arrow(start, end): return .arrow(from: move(start), to: move(end))
        case let .rectangle(rect): return .rectangle(rect.offsetBy(dx: dx, dy: dy))
        case let .ellipse(rect): return .ellipse(rect.offsetBy(dx: dx, dy: dy))
        case let .text(string, origin): return .text(string, at: move(origin))
        }
    }

    /// The points a selected annotation can be dragged by: the ends of a line, the
    /// corners of a rectangle or ellipse. Freehand strokes and text only move.
    public var handles: [(handle: AnnotationHandle, point: CGPoint)] {
        switch self {
        case let .line(start, end), let .arrow(start, end):
            return [(.start, start), (.end, end)]
        case let .rectangle(rect), let .ellipse(rect):
            return [
                (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
                (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
                (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
                (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            ]
        case .pen, .highlighter, .text:
            return []
        }
    }

    /// The shape with `handle` dragged to `point`; the opposite end or corner stays.
    /// `constrained` (⇧): lines in steps of 45°, squares and circles.
    public func moving(_ handle: AnnotationHandle, to point: CGPoint, constrained: Bool = false) -> AnnotationShape {
        switch self {
        case let .line(start, end), let .arrow(start, end):
            let fixed = handle == .start ? end : start
            let moved = constrained ? AnnotationGeometry.snapped(point, from: fixed) : point
            let newStart = handle == .start ? moved : start
            let newEnd = handle == .start ? end : moved
            if case .arrow = self {
                return .arrow(from: newStart, to: newEnd)
            }
            return .line(from: newStart, to: newEnd)
        case let .rectangle(rect), let .ellipse(rect):
            let fixed: CGPoint
            switch handle {
            case .topLeft: fixed = CGPoint(x: rect.maxX, y: rect.maxY)
            case .topRight: fixed = CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomLeft: fixed = CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomRight, .start, .end: fixed = CGPoint(x: rect.minX, y: rect.minY)
            }
            let moved = AnnotationGeometry.rect(from: fixed, to: point, square: constrained)
            if case .ellipse = self {
                return .ellipse(moved)
            }
            return .rectangle(moved)
        case .pen, .highlighter, .text:
            return self
        }
    }
}

public enum AnnotationHandle: Sendable, Equatable {
    case start
    case end
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// One mark on the picture: an arrow, a stroke, a box, a comment …
public struct Annotation: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var shape: AnnotationShape
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle) {
        self.id = id
        self.shape = shape
        self.style = style
    }

    public var tool: AnnotationTool {
        shape.tool
    }
}
