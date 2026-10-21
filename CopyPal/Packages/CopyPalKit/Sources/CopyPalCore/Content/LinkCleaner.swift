import Foundation

/// Removes tracking parameters from a link (utm_*, fbclid, gclid …) when it is pasted
/// without formatting. Path, the other parameters and the fragment stay as they were.
public enum LinkCleaner {
    /// Parameter names that only say where a click came from.
    static let trackingNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "li_fat_id", "igshid", "igsh", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "_ga", "_gl",
        "oly_anon_id", "oly_enc_id", "vero_id", "rb_clickid", "s_cid", "wickedid", "spm",
    ]

    static let trackingPrefixes = ["utm_", "pk_", "mtm_"]

    /// The link without tracking parameters, or nil when `text` is not a single http(s)
    /// link or carries none (then it is pasted unchanged).
    public static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LinkParser.parse(trimmed) != nil,
              var components = URLComponents(string: trimmed),
              let items = components.percentEncodedQueryItems, !items.isEmpty else {
            return nil
        }
        let kept = items.filter { !isTracking($0.name) }
        guard kept.count < items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string
    }

    static func isTracking(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return trackingNames.contains(lowercased) || trackingPrefixes.contains { lowercased.hasPrefix($0) }
    }
}
