import Foundation

/// Recognizes a color written as text: `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`,
/// `rgb()`/`rgba()` and `hsl()`/`hsla()` (CSS syntax, commas or spaces).
public enum ColorParser {
    public static func parse(_ text: String) -> ColorValue? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, value.count <= 64 else { return nil }
        if value.hasPrefix("#") {
            return parseHex(String(value.dropFirst()))
        }
        if let arguments = functionArguments(value, names: ["rgb", "rgba"]) {
            return parseRGB(arguments)
        }
        if let arguments = functionArguments(value, names: ["hsl", "hsla"]) {
            return parseHSL(arguments)
        }
        return nil
    }

    static func parseHex(_ digits: String) -> ColorValue? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded = digits.count <= 4 ? digits.map { "\($0)\($0)" }.joined() : digits
        var bytes: [Double] = []
        var index = expanded.startIndex
        while index < expanded.endIndex {
            let next = expanded.index(index, offsetBy: 2)
            guard let byte = UInt8(expanded[index..<next], radix: 16) else { return nil }
            bytes.append(Double(byte) / 255)
            index = next
        }
        return ColorValue(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes.count == 4 ? bytes[3] : 1)
    }

    /// "rgb(255, 136, 0)" → ["255", "136", "0"]; also "rgb(255 136 0 / 50%)".
    static func functionArguments(_ value: String, names: [String]) -> [String]? {
        guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else { return nil }
        let name = value[..<open].trimmingCharacters(in: .whitespaces)
        guard names.contains(name) else { return nil }
        let inner = value[value.index(after: open)..<value.index(before: value.endIndex)]
        let parts = inner
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        return (3...4).contains(parts.count) ? parts : nil
    }

    static func parseRGB(_ parts: [String]) -> ColorValue? {
        var channels: [Double] = []
        for part in parts.prefix(3) {
            guard let value = number(part, percentOf: 255), (0...255).contains(value) else { return nil }
            channels.append(value / 255)
        }
        guard let alpha = parts.count == 4 ? alphaValue(parts[3]) : 1 else { return nil }
        return ColorValue(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    static func parseHSL(_ parts: [String]) -> ColorValue? {
        let hueText = parts[0].hasSuffix("deg") ? String(parts[0].dropLast(3)) : parts[0]
        guard let hue = Double(hueText),
              parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
              let saturation = Double(parts[1].dropLast()), let lightness = Double(parts[2].dropLast()),
              (0...100).contains(saturation), (0...100).contains(lightness),
              let alpha = parts.count == 4 ? alphaValue(parts[3]) : 1
        else {
            return nil
        }
        let (red, green, blue) = hslToRGB(
            hue: hue.truncatingRemainder(dividingBy: 360) / 360,
            saturation: saturation / 100,
            lightness: lightness / 100
        )
        return ColorValue(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func number(_ text: String, percentOf scale: Double) -> Double? {
        if text.hasSuffix("%") {
            return Double(text.dropLast()).map { $0 / 100 * scale }
        }
        return Double(text)
    }

    private static func alphaValue(_ text: String) -> Double? {
        guard let value = number(text, percentOf: 1), (0...1).contains(value) else { return nil }
        return value
    }

    static func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> (Double, Double, Double) {
        let hue = hue < 0 ? hue + 1 : hue
        guard saturation > 0 else { return (lightness, lightness, lightness) }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return (channel(hue + 1 / 3), channel(hue), channel(hue - 1 / 3))
    }
}
