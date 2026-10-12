import Foundation

public struct SensitiveDetectionOptions: Sendable, Equatable {
    /// 6-digit codes ("123456", "123 456") count as one-time codes.
    public var detectOneTimeCodes: Bool

    public init(detectOneTimeCodes: Bool = true) {
        self.detectOneTimeCodes = detectOneTimeCodes
    }
}

public struct SensitiveMatch: Sendable, Equatable {
    public var kind: Sensitivity
    /// Shown instead of the content, e.g. "DE89 •••• 3000".
    public var masked: String
}

/// Finds content that should not stay in the history: IBANs (mod-97 check), card
/// numbers (issuer range + Luhn), API keys and tokens of well-known services, private
/// keys and – optionally – one-time codes. Deliberately conservative: checksums and
/// fixed prefixes keep phone and order numbers out (ROADMAP R11).
public enum SensitiveContentDetector {
    /// Texts longer than this are only checked for keys and tokens.
    static let shortTextLimit = 500
    static let scanLimit = 20_000

    public static func detect(_ text: String, options: SensitiveDetectionOptions = SensitiveDetectionOptions()) -> SensitiveMatch? {
        let sample = text.count > scanLimit ? String(text.prefix(scanLimit)) : text
        if let secret = SecretPatterns.firstMatch(in: sample) {
            return SensitiveMatch(kind: .secret, masked: secret)
        }
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= shortTextLimit else { return nil }
        if let iban = IBAN.find(in: trimmed) {
            return SensitiveMatch(kind: .iban, masked: IBAN.mask(iban))
        }
        if let card = PaymentCard.find(in: trimmed) {
            return SensitiveMatch(kind: .card, masked: "•••• " + card.suffix(4))
        }
        if options.detectOneTimeCodes, OneTimeCode.matches(trimmed) {
            return SensitiveMatch(kind: .oneTimeCode, masked: "••••••")
        }
        return nil
    }
}

// MARK: IBAN

enum IBAN {
    /// Total length per country (SWIFT IBAN registry).
    static let lengths: [String: Int] = [
        "AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16, "BG": 22, "BH": 22, "BI": 27,
        "BR": 29, "BY": 28, "CH": 21, "CR": 22, "CY": 28, "CZ": 24, "DE": 22, "DJ": 27, "DK": 18, "DO": 28,
        "EE": 20, "EG": 29, "ES": 24, "FI": 18, "FK": 18, "FO": 18, "FR": 27, "GB": 22, "GE": 22, "GI": 23,
        "GL": 18, "GR": 27, "GT": 28, "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27,
        "JO": 30, "KW": 30, "KZ": 20, "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20, "LV": 21, "LY": 25,
        "MC": 27, "MD": 24, "ME": 22, "MK": 19, "MN": 20, "MR": 27, "MT": 31, "MU": 30, "NI": 28, "NL": 18,
        "NO": 15, "OM": 23, "PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29, "RO": 24, "RS": 22, "RU": 33,
        "SA": 24, "SC": 31, "SD": 18, "SE": 24, "SI": 19, "SK": 24, "SM": 27, "SO": 23, "ST": 25, "SV": 28,
        "TL": 23, "TN": 24, "TR": 26, "UA": 29, "VA": 22, "VG": 24, "XK": 20, "YE": 30,
    ]

    /// The first valid IBAN in `text` (spaces between groups allowed), normalized.
    static func find(in text: String) -> String? {
        let characters = Array(text.uppercased())
        var start = 0
        while start + 4 < characters.count {
            defer { start += 1 }
            // Must start at a word boundary with two letters and two digits.
            if start > 0, characters[start - 1].isLetter || characters[start - 1].isNumber { continue }
            let prefix = String(characters[start..<start + 2])
            guard let length = lengths[prefix], characters[start + 2].isNumber, characters[start + 3].isNumber else { continue }

            var compact = ""
            var index = start
            while index < characters.count, compact.count < length {
                let character = characters[index]
                if character.isASCII, character.isLetter || character.isNumber {
                    compact.append(character)
                } else if character == " ", index + 1 < characters.count, characters[index + 1] != " " {
                    // single spaces between groups
                } else {
                    break
                }
                index += 1
            }
            let endsAtBoundary = index >= characters.count || !(characters[index].isLetter || characters[index].isNumber)
            if compact.count == length, endsAtBoundary, isValid(compact) {
                return compact
            }
        }
        return nil
    }

    /// ISO 13616: move the first four characters to the end, letters → 10…35, mod 97 = 1.
    static func isValid(_ iban: String) -> Bool {
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            if let digit = character.wholeNumberValue, character.isASCII {
                remainder = (remainder * 10 + digit) % 97
            } else if let ascii = character.asciiValue, character.isLetter {
                remainder = (remainder * 100 + Int(ascii) - 55) % 97
            } else {
                return false
            }
        }
        return remainder == 1
    }

    static func mask(_ iban: String) -> String {
        "\(iban.prefix(4)) •••• \(iban.suffix(4))"
    }
}

// MARK: Payment cards

enum PaymentCard {
    /// The first card number (13–19 digits, optionally grouped by spaces or dashes)
    /// with a known issuer prefix and a valid Luhn checksum.
    static func find(in text: String) -> String? {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            guard characters[index].isASCII, characters[index].isNumber,
                  index == 0 || !(characters[index - 1].isNumber || characters[index - 1].isLetter) else {
                index += 1
                continue
            }
            var digits = ""
            var cursor = index
            var separator: Character?
            while cursor < characters.count {
                let character = characters[cursor]
                if character.isASCII, character.isNumber {
                    digits.append(character)
                } else if character == " " || character == "-", cursor + 1 < characters.count, characters[cursor + 1].isNumber {
                    if separator == nil { separator = character }
                    guard character == separator else { break }
                } else {
                    break
                }
                cursor += 1
            }
            let endsAtBoundary = cursor >= characters.count || !characters[cursor].isLetter
            if endsAtBoundary, (13...19).contains(digits.count), hasKnownIssuer(digits), passesLuhn(digits) {
                return digits
            }
            index = cursor + 1
        }
        return nil
    }

    static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (offset, character) in digits.reversed().enumerated() {
            guard var digit = character.wholeNumberValue else { return false }
            if offset % 2 == 1 {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
        }
        return sum % 10 == 0
    }

    /// Visa, Mastercard, Amex, Discover, JCB, Diners, UnionPay, Maestro.
    static func hasKnownIssuer(_ digits: String) -> Bool {
        func prefix(_ length: Int) -> Int {
            Int(digits.prefix(length)) ?? -1
        }
        let count = digits.count
        switch true {
        case digits.hasPrefix("4"): return [13, 16, 19].contains(count)
        case (51...55).contains(prefix(2)), (2221...2720).contains(prefix(4)): return count == 16
        case [34, 37].contains(prefix(2)): return count == 15
        case prefix(4) == 6011, prefix(2) == 65, (644...649).contains(prefix(3)): return (16...19).contains(count)
        case (3528...3589).contains(prefix(4)): return (16...19).contains(count)
        case (300...305).contains(prefix(3)), [36, 38, 39].contains(prefix(2)): return (14...19).contains(count)
        case prefix(2) == 62: return (16...19).contains(count)
        case [50, 56, 57, 58, 67].contains(prefix(2)): return (12...19).contains(count)
        default: return false
        }
    }
}

// MARK: Keys and tokens

enum SecretPatterns {
    /// `@unchecked`: NSRegularExpression is immutable and thread-safe once created, but
    /// not marked Sendable in every SDK.
    struct Pattern: @unchecked Sendable {
        let regex: NSRegularExpression
        /// Characters of the match kept visible in the masked form.
        let visiblePrefix: Int
    }

    static let patterns: [Pattern] = [
        (#"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#, 4), // AWS access key ID
        (#"(?i)aws_secret_access_key\s*[=:]\s*[A-Za-z0-9/+=]{40}"#, 0),
        (#"\bgh[pousr]_[A-Za-z0-9]{36}\b"#, 4), // GitHub tokens
        (#"\bgithub_pat_[A-Za-z0-9_]{60,}"#, 11),
        (#"\bxox[baprs]-[A-Za-z0-9-]{10,}"#, 5), // Slack tokens
        (#"https://hooks\.slack\.com/services/[A-Za-z0-9/]{20,}"#, 0),
        (#"\b[rs]k_(live|test)_[A-Za-z0-9]{16,}"#, 8), // Stripe secret and restricted keys
        (#"\bsk-ant-[A-Za-z0-9_-]{20,}"#, 7), // Anthropic
        (#"\bsk-(proj-|svcacct-)?[A-Za-z0-9_-]{32,}"#, 3), // OpenAI
        (#"\bAIza[0-9A-Za-z_-]{35}\b"#, 4), // Google API key
        (#"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, 3), // JWT
        (#"-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----"#, 0), // PEM / OpenSSH / PGP private keys
    ].map { pattern, visible in
        // Fixed literals: compiling them cannot fail.
        Pattern(regex: try! NSRegularExpression(pattern: pattern), visiblePrefix: visible)
    }

    /// The masked first match, e.g. "AKIA••••••••".
    static func firstMatch(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range, in: text) else { continue }
            let token = text[swiftRange]
            return String(token.prefix(pattern.visiblePrefix)) + "••••••••"
        }
        return nil
    }
}

// MARK: One-time codes

enum OneTimeCode {
    /// "123456", "123 456", "123-456" – the whole text, nothing else.
    static func matches(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard digits.count == 6, digits.allSatisfy(\.isASCII) else { return false }
        if text.count == 6 { return true }
        guard text.count == 7 else { return false }
        let separator = text[text.index(text.startIndex, offsetBy: 3)]
        return separator == " " || separator == "-"
    }
}
