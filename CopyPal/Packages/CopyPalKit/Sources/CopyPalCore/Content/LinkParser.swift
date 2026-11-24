import Foundation

public enum LinkParser {
    /// A single http(s) URL (surrounding whitespace allowed), split into host and path.
    public static func parse(_ text: String) -> LinkInfo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4_096,
              !trimmed.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = components.host, !rawHost.isEmpty, rawHost.contains(".") || rawHost == "localhost"
        else {
            return nil
        }
        let lowercased = rawHost.lowercased()
        let host = lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
        var path = components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty {
            path += "?" + query
        }
        if path == "/" { path = "" }
        let decoded = path.removingPercentEncoding ?? path
        return LinkInfo(url: trimmed, host: host, path: decoded)
    }
}
