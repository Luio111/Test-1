import Foundation

/// Whether this copy of CopyPal may be used (ROADMAP §1.4, decision 10). Version 1
/// is always licensed; if D11 decides on a paid version, a provider that checks a
/// license key offline (signature, no server) replaces `AlwaysLicensed` without
/// touching the rest of the app.
protocol LicenseProvider: Sendable {
    var state: LicenseState { get }
}

enum LicenseState: Equatable, Sendable {
    case licensed
    case trial(daysLeft: Int)
    case expired
}

struct AlwaysLicensed: LicenseProvider {
    var state: LicenseState { .licensed }
}
