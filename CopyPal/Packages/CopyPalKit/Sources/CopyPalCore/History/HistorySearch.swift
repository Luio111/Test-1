import Foundation

public enum HistorySearch {
    /// Entries matching every word of `query` (case and accents ignored). Entries with a
    /// word starting with the first query word come first; within both groups the
    /// input order (most recent first) is kept. Sensitive entries are never found.
    public static func filter(_ items: [ClipItem], query: String) -> [ClipItem] {
        let words = TextFolding.fold(query).split(separator: " ").map(String.init)
        guard let first = words.first else { return items }

        var prefixMatches: [ClipItem] = []
        var otherMatches: [ClipItem] = []
        for item in items where !item.isSensitive {
            let haystack = searchableText(of: item)
            guard words.allSatisfy(haystack.contains) else { continue }
            if haystack.hasPrefix(first) || haystack.contains(" " + first) {
                prefixMatches.append(item)
            } else {
                otherMatches.append(item)
            }
        }
        return prefixMatches + otherMatches
    }

    static func searchableText(of item: ClipItem) -> String {
        var text = item.preview.searchText
        if let label = item.pinLabel, !label.isEmpty {
            text = TextFolding.fold(label) + " " + text
        }
        return text
    }
}
