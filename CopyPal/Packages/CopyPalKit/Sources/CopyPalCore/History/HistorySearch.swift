import Foundation

public enum HistorySearch {
    /// Entries matching every word of `query` (case and accents ignored). Entries with a
    /// word starting with the first query word come first; within each group the input
    /// order (most recent first) is kept. Besides the content, the source app's name
    /// (`appNames`: bundle ID → name) and words for the kind ("bild", "link", …) are
    /// searched; entries found only through those come last. Sensitive entries are
    /// never found.
    public static func filter(_ items: [ClipItem], query: String, appNames: [String: String] = [:]) -> [ClipItem] {
        let words = TextFolding.fold(query).split(separator: " ").map(String.init)
        guard let first = words.first else { return items }

        var prefixMatches: [ClipItem] = []
        var otherMatches: [ClipItem] = []
        var contextMatches: [ClipItem] = []
        for item in items where !item.isSensitive {
            let content = searchableText(of: item)
            if words.allSatisfy(content.contains) {
                if content.hasPrefix(first) || content.contains(" " + first) {
                    prefixMatches.append(item)
                } else {
                    otherMatches.append(item)
                }
                continue
            }
            let context = content + " " + contextText(of: item, appNames: appNames)
            if words.allSatisfy(context.contains) {
                contextMatches.append(item)
            }
        }
        return prefixMatches + otherMatches + contextMatches
    }

    static func searchableText(of item: ClipItem) -> String {
        var text = item.preview.searchText
        if let label = item.pinLabel, !label.isEmpty {
            text = TextFolding.fold(label) + " " + text
        }
        return text
    }

    /// The source app and the kind, in German and English (the words people type).
    static func contextText(of item: ClipItem, appNames: [String: String]) -> String {
        var parts = [kindWords(item.kind)]
        if item.preview.capturedFrom != nil {
            parts.append("bildschirmfoto screenshot")
        }
        if let bundleID = item.sourceBundleID, let name = appNames[bundleID], !name.isEmpty {
            parts.append(TextFolding.fold(name))
        }
        return parts.joined(separator: " ")
    }

    static func kindWords(_ kind: ClipKind) -> String {
        switch kind {
        case .text: "text"
        case .richText: "text formatiert formatted"
        case .link: "link url"
        case .color: "farbe color"
        case .image: "bild image foto"
        case .files: "datei dateien file files"
        case .other: ""
        }
    }
}
