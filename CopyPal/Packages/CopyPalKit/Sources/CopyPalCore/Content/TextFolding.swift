import Foundation

public enum TextFolding {
    /// Lowercased, without diacritics ("Café" → "cafe"), whitespace collapsed. Used for
    /// both the stored search text and the query.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// First non-empty line, trimmed and shortened for list rows.
    public static func firstLine(of text: String, maxLength: Int = 300) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > maxLength ? String(line.prefix(maxLength)) + "…" : line
    }

    public static func lineCount(of text: String) -> Int {
        max(1, text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
    }
}
