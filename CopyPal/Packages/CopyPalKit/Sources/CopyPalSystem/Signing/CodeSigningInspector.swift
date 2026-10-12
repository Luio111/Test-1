#if os(macOS)
import Foundation
import Security
import CopyPalCore

/// Reads the signature of the running app. Used by the diagnostics window to catch
/// ad-hoc builds early: macOS ties privacy grants to the signature, so an unstable
/// signature makes the Accessibility grant disappear after every rebuild.
public enum CodeSigningInspector {
    public static func currentProcess() -> SigningStatus {
        var code: SecCode?
        var status = SecCodeCopySelf(SecCSFlags(), &code)
        guard status == errSecSuccess, let code else {
            return .unknown("SecCodeCopySelf \(status)")
        }

        var staticCode: SecStaticCode?
        status = SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard status == errSecSuccess, let staticCode else {
            return .unknown("SecCodeCopyStaticCode \(status)")
        }

        var information: CFDictionary?
        status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard status == errSecSuccess, let info = information as? [String: Any] else {
            return .unknown("SecCodeCopySigningInformation \(status)")
        }
        return classify(info)
    }

    static func classify(_ info: [String: Any]) -> SigningStatus {
        guard info[kSecCodeInfoIdentifier as String] != nil else {
            return .unsigned
        }
        if let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value,
           flags & SecCodeSignatureFlags.adhoc.rawValue != 0 {
            return .adHoc
        }
        guard let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String, !teamID.isEmpty else {
            return .adHoc
        }
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let summary = certificates?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        return .developer(teamID: teamID, certificate: summary)
    }
}
#endif
