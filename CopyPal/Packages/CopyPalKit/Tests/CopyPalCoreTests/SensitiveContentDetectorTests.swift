import Foundation
import Testing
@testable import CopyPalCore

/// Test corpus for sensitive content (ROADMAP M5: at least 50 examples, 0 errors).
/// Token-like strings are assembled at runtime from documented example values, so
/// GitHub's push protection does not mistake them for real secrets.
struct SensitiveContentDetectorTests {
    static func repeated(_ unit: String, _ count: Int) -> String {
        String(repeating: unit, count: count)
    }

    static let positives: [(String, Sensitivity)] = [
        // IBAN (examples from the national banks' documentation)
        ("DE89 3704 0044 0532 0130 00", .iban),
        ("DE89370400440532013000", .iban),
        ("de89 3704 0044 0532 0130 00", .iban),
        ("IBAN: DE89 3704 0044 0532 0130 00", .iban),
        ("Bitte überweisen an DE89 3704 0044 0532 0130 00, danke!", .iban),
        ("GB82 WEST 1234 5698 7654 32", .iban),
        ("FR14 2004 1010 0505 0001 3M02 606", .iban),
        ("NL91ABNA0417164300", .iban),
        ("AT61 1904 3002 3457 3201", .iban),
        ("CH93 0076 2011 6238 5295 7", .iban),
        ("BE68 5390 0754 7034", .iban),
        ("ES91 2100 0418 4502 0005 1332", .iban),
        ("IT60 X054 2811 1010 0000 0123 456", .iban),
        ("NO93 8601 1117 947", .iban),
        // Payment cards (public test numbers)
        ("4242 4242 4242 4242", .card),
        ("4242424242424242", .card),
        ("4111-1111-1111-1111", .card),
        ("5555 5555 5555 4444", .card),
        ("2223 0031 2200 3222", .card),
        ("3782 822463 10005", .card),
        ("6011 1111 1111 1117", .card),
        ("3530 1113 3330 0000", .card),
        ("3056 9309 0259 04", .card),
        ("6200 0000 0000 0005", .card),
        ("Karte: 4000 0566 5566 5556 (gültig bis 12/28)", .card),
        // Keys and tokens
        ("AKIAIOSFODNN7EXAMPLE", .secret),
        ("export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE", .secret),
        ("aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", .secret),
        ("gh" + "p_" + repeated("a1B2", 9), .secret),
        ("GITHUB_TOKEN=gh" + "o_" + repeated("Z9y8", 9), .secret),
        ("github" + "_pat_" + repeated("A1b2C3", 14), .secret),
        ("xo" + "xb-" + "1234567890-" + repeated("Ab", 12), .secret),
        ("https://hooks.slack.com/services/" + "T00000000/B00000000/" + repeated("X", 24), .secret),
        ("sk" + "_live_" + repeated("4eC3", 6), .secret),
        ("rk" + "_test_" + repeated("51Hx", 6), .secret),
        ("sk-" + "ant-api03-" + repeated("Ab9_", 20), .secret),
        ("sk-" + "proj-" + repeated("x1Y2", 12), .secret),
        ("AI" + "za" + "SyD-" + repeated("a", 31), .secret),
        ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c", .secret),
        ("Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhYmMxMjMifQ.c2lnbmF0dXJlX3Rlc3Q", .secret),
        ("-----BEGIN RSA " + "PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----", .secret),
        ("-----BEGIN OPENSSH " + "PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA", .secret),
        ("-----BEGIN " + "PRIVATE KEY-----", .secret),
        ("-----BEGIN PGP " + "PRIVATE KEY BLOCK-----", .secret),
        (repeated("Viel Text davor. ", 100) + "gh" + "p_" + repeated("q7W8", 9), .secret),
        // One-time codes
        ("123456", .oneTimeCode),
        ("834 221", .oneTimeCode),
        ("834-221", .oneTimeCode),
        ("  654321\n", .oneTimeCode),
    ]

    static let negatives: [String] = [
        "DE88 3704 0044 0532 0130 00", // wrong check digits
        "DE89 3704 0044 0532 0130", // too short
        "DE89 3704 0044 0532 0130 000", // too long
        "XX89 3704 0044 0532 0130 00", // no such country
        "4242 4242 4242 4241", // Luhn fails
        "1234 5678 9012 3452", // Luhn ok, but no card issuer
        "4242 4242-4242 4242", // mixed separators
        "+49 170 1234567",
        "0170 1234567",
        "Telefon: 030 12345678",
        "Bestellnummer 302-1234567-8901234",
        "Rechnung Nr. 2026-000123",
        "Tracking 1Z999AA10123456784",
        "ISBN 978-3-16-148410-0",
        "PLZ 10115",
        "12345",
        "1234567",
        "12 34 56",
        "2026",
        "Kontonummer 1234567890",
        "BLZ 370 400 44",
        "Summe 1.234,56 €",
        "Datum 12.10.2026, 12:30 Uhr",
        "Seriennummer C02XL0GTJGH5",
        "123e4567-e89b-12d3-a456-426614174000",
        "https://example.com/?id=1234567890123456",
        "Hallo Welt",
        "AKIA1234", // too short
        "sk-test", // too short
        "pk" + "_live_" + repeated("4eC3", 6), // publishable key, not secret
        "eyJhbGciOiJIUzI1NiJ9", // JWT header alone
        "-----BEGIN PUBLIC KEY-----",
        "-----BEGIN CERTIFICATE-----",
        "Das Passwort steht im Tresor.",
        "#FF8800",
        "https://github.com/Luio111/Test-1/pull/2",
        repeated("Langer Text. ", 50) + "DE89 3704 0044 0532 0130 00", // long texts: IBAN not checked
    ]

    @Test(arguments: positives)
    func detects(text: String, kind: Sensitivity) {
        #expect(SensitiveContentDetector.detect(text)?.kind == kind)
    }

    @Test(arguments: negatives)
    func ignores(text: String) {
        #expect(SensitiveContentDetector.detect(text) == nil)
    }

    @Test func corpusIsLargeEnough() {
        #expect(Self.positives.count + Self.negatives.count >= 50)
    }

    @Test func oneTimeCodesCanBeTurnedOff() {
        let options = SensitiveDetectionOptions(detectOneTimeCodes: false)
        #expect(SensitiveContentDetector.detect("123456", options: options) == nil)
        #expect(SensitiveContentDetector.detect("4242 4242 4242 4242", options: options)?.kind == .card)
    }

    @Test func masks() {
        #expect(SensitiveContentDetector.detect("DE89 3704 0044 0532 0130 00")?.masked == "DE89 •••• 3000")
        #expect(SensitiveContentDetector.detect("4242 4242 4242 4242")?.masked == "•••• 4242")
        #expect(SensitiveContentDetector.detect("AKIAIOSFODNN7EXAMPLE")?.masked == "AKIA••••••••")
        #expect(SensitiveContentDetector.detect("123456")?.masked == "••••••")
    }

    @Test func maskNeverContainsTheSecretPart() throws {
        for (text, _) in Self.positives {
            let masked = try #require(SensitiveContentDetector.detect(text)?.masked)
            #expect(masked.count < 20 || !text.contains(masked))
            #expect(masked.contains("•"))
        }
    }
}
