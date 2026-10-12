#if os(macOS)
import Foundation
import Security
import Testing
@testable import CopyPalSystem
import CopyPalCore

struct CodeSigningInspectorTests {
    @Test func missingIdentifierMeansUnsigned() {
        #expect(CodeSigningInspector.classify([:]) == .unsigned)
    }

    @Test func adHocFlagWins() {
        let info: [String: Any] = [
            kSecCodeInfoIdentifier as String: "io.example.CopyPal",
            kSecCodeInfoFlags as String: NSNumber(value: SecCodeSignatureFlags.adhoc.rawValue),
        ]
        #expect(CodeSigningInspector.classify(info) == .adHoc)
    }

    @Test func teamIdentifierMeansDeveloperSigned() {
        let info: [String: Any] = [
            kSecCodeInfoIdentifier as String: "io.example.CopyPal",
            kSecCodeInfoFlags as String: NSNumber(value: 0),
            kSecCodeInfoTeamIdentifier as String: "ABCDE12345",
        ]
        #expect(CodeSigningInspector.classify(info) == .developer(teamID: "ABCDE12345", certificate: nil))
    }

    @Test func signedWithoutTeamIsTreatedAsAdHoc() {
        let info: [String: Any] = [kSecCodeInfoIdentifier as String: "io.example.CopyPal"]
        #expect(CodeSigningInspector.classify(info) == .adHoc)
    }

    @Test func currentProcessDoesNotCrash() {
        // The test runner's own signature varies by machine; only check it resolves.
        _ = CodeSigningInspector.currentProcess()
    }
}
#endif
