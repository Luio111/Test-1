/// Formats the Xcode/SDK values Xcode writes into the built app's Info.plist
/// (`DTXcode` like "1640", `DTSDKName` like "macosx15.5").
public enum BuildEnvironment {
    public static func describe(xcode: String?, sdk: String?) -> String {
        let parts = [xcode.flatMap(xcodeVersion).map { "Xcode \($0)" }, sdk].compactMap { $0 }
        return parts.isEmpty ? "unbekannt" : parts.joined(separator: " · ")
    }

    /// "1640" → "16.4", "2601" → "26.0.1", "0941" → "9.4.1"
    static func xcodeVersion(_ raw: String) -> String? {
        guard raw.count >= 3, raw.allSatisfy(\.isNumber), let major = Int(raw.dropLast(2)) else {
            return nil
        }
        let minor = raw.dropFirst(raw.count - 2).prefix(1)
        let patch = raw.suffix(1)
        return patch == "0" ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}
