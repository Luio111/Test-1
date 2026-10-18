import Foundation

public struct LinkInfo: Sendable, Equatable, Codable {
    public var url: String
    public var host: String
    /// Path with query, without the scheme and host; empty for the root.
    public var path: String

    public init(url: String, host: String, path: String) {
        self.url = url
        self.host = host
        self.path = path
    }
}

/// An sRGB color with components in 0…1.
public struct ColorValue: Sendable, Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#RRGGBB", or "#RRGGBBAA" when not opaque.
    public var hex: String {
        func byte(_ value: Double) -> String {
            let clamped = Int((min(max(value, 0), 1) * 255).rounded())
            let digits = String(clamped, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }
        let rgb = "#" + byte(red) + byte(green) + byte(blue)
        return alpha < 1 ? rgb + byte(alpha) : rgb
    }
}

public struct PixelSize: Sendable, Equatable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// What the popup and the history show for an entry. Stored encrypted; holds data
/// only, the app formats it for display.
public struct ClipPreview: Sendable, Equatable, Codable {
    /// First non-empty line (text), URL, color value, file name(s) …
    public var title: String
    public var lineCount: Int
    public var characterCount: Int
    public var link: LinkInfo?
    public var color: ColorValue?
    public var fileNames: [String]
    public var imageSize: PixelSize?
    /// Carries formatting (RTF/HTML) in addition to plain text.
    public var isFormatted: Bool
    /// Masked form for sensitive entries, e.g. "DE89 •••• 3000"; shown instead of `title`.
    public var masked: String?
    /// Case- and accent-folded text the search runs on (truncated).
    public var searchText: String
    /// Set for screenshots: the app and window they show ("Safari – JIRA-1234"), empty
    /// when unknown. Nil for every other entry (also in previews stored before).
    public var capturedFrom: String?

    public init(
        title: String,
        lineCount: Int = 1,
        characterCount: Int = 0,
        link: LinkInfo? = nil,
        color: ColorValue? = nil,
        fileNames: [String] = [],
        imageSize: PixelSize? = nil,
        isFormatted: Bool = false,
        masked: String? = nil,
        searchText: String = "",
        capturedFrom: String? = nil
    ) {
        self.title = title
        self.lineCount = lineCount
        self.characterCount = characterCount
        self.link = link
        self.color = color
        self.fileNames = fileNames
        self.imageSize = imageSize
        self.isFormatted = isFormatted
        self.masked = masked
        self.searchText = searchText
        self.capturedFrom = capturedFrom
    }
}
