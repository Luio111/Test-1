import Foundation
import Testing
@testable import CopyPalCore

struct DiagnosticsReportTests {
    private func snapshot(
        signing: SigningStatus = .developer(teamID: "ABCDE12345", certificate: "Apple Development: Jane Doe (XYZ123)"),
        accessibility: PermissionState = .granted,
        access: PasteboardAccessStatus = .alwaysAllow,
        probe: PasteboardProbe? = nil,
        screenCapture: PermissionState? = nil
    ) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            appVersion: "0.1.0",
            buildNumber: "1",
            bundleIdentifier: "io.example.CopyPal.dev",
            buildEnvironment: "Xcode 16.4 · macosx15.5",
            osVersion: "Version 26.1 (Build 25B78)",
            signing: signing,
            accessibility: accessibility,
            pasteboardAccess: access,
            pasteboardProbe: probe,
            screenCapture: screenCapture,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func healthySetupHasNoWarnings() {
        let report = DiagnosticsReport.text(for: snapshot())
        #expect(report.contains("Signatur: Team ABCDE12345 – Apple Development"))
        #expect(report.contains("Gebaut mit: Xcode 16.4 · macosx15.5"))
        #expect(report.contains("Bedienungshilfen: erteilt"))
        #expect(report.contains("Bildschirmaufnahme: – (Bildschirmfoto aus)"))
        #expect(report.contains("Lesetest: nicht ausgeführt"))
        #expect(report.contains("Zeitpunkt: 1970-01-01T00:00:00Z"))
        #expect(!report.contains("Hinweis:"))
    }

    @Test func screenCaptureIsReportedAndFlagged() {
        let granted = DiagnosticsReport.text(for: snapshot(screenCapture: .granted))
        #expect(granted.contains("Bildschirmaufnahme: erteilt"))
        #expect(DiagnosticsWarning.warnings(for: snapshot(screenCapture: .granted)).isEmpty)
        let denied = snapshot(screenCapture: .denied)
        #expect(DiagnosticsReport.text(for: denied).contains("Bildschirmaufnahme: nicht erteilt"))
        #expect(DiagnosticsWarning.warnings(for: denied) == [.screenCaptureDenied])
        #expect(DiagnosticsWarning.warnings(for: snapshot(screenCapture: nil)).isEmpty)
    }

    @Test func reportNeverContainsCertificateHolder() {
        let report = DiagnosticsReport.text(for: snapshot())
        #expect(!report.contains("Jane Doe"))
        #expect(!report.contains("XYZ123"))
    }

    @Test(arguments: [
        ("Apple Development: jane@example.com (XYZ123)", "Apple Development"),
        ("Developer ID Application: Jane Doe (ABCDE12345)", "Developer ID Application"),
        ("no colon here", nil),
    ] as [(String, String?)])
    func certificateKind(summary: String, kind: String?) {
        #expect(DiagnosticsReport.certificateKind(summary) == kind)
    }

    @Test func teamWithoutCertificateSummary() {
        #expect(DiagnosticsReport.describe(.developer(teamID: "ABCDE12345", certificate: nil)) == "Team ABCDE12345")
    }

    @Test(arguments: [SigningStatus.adHoc, .unsigned, .unknown("x")])
    func unstableSignatureIsFlagged(signing: SigningStatus) {
        #expect(!signing.isStable)
        #expect(DiagnosticsWarning.warnings(for: snapshot(signing: signing)) == [.unstableSigning])
    }

    @Test func missingAccessibilityIsFlagged() {
        #expect(DiagnosticsWarning.warnings(for: snapshot(accessibility: .denied)) == [.accessibilityDenied])
    }

    @Test(arguments: [
        (PasteboardAccessStatus.unavailable, nil),
        (.alwaysAllow, nil),
        (.systemDefault, .pasteboardMayAsk),
        (.ask, .pasteboardMayAsk),
        (.alwaysDeny, .pasteboardDenied),
        (.notInBuildSDK, .pasteboardStatusUnknown),
        (.unknown(rawValue: 9), .pasteboardStatusUnknown),
    ] as [(PasteboardAccessStatus, DiagnosticsWarning?)])
    func pasteboardAccessWarning(access: PasteboardAccessStatus, warning: DiagnosticsWarning?) {
        #expect(access.mayInterruptCapture == (warning != nil))
        #expect(DiagnosticsWarning.warnings(for: snapshot(access: access)) == (warning.map { [$0] } ?? []))
    }

    @Test func everyWarningHasReportText() {
        for warning in DiagnosticsWarning.allCases {
            #expect(!DiagnosticsReport.text(for: warning).isEmpty)
        }
    }

    @Test func probeListsTypesButNoContents() {
        let probe = PasteboardProbe(
            changeCount: 42,
            types: ["public.utf8-plain-text", "public.html"],
            duration: .microseconds(1_500)
        )
        let report = DiagnosticsReport.text(for: snapshot(probe: probe))
        #expect(report.contains("Lesetest: Änderungszähler 42, Formate: 2, 1.50 ms – public.utf8-plain-text, public.html"))
    }

    @Test func emptyPasteboardProbe() {
        let probe = PasteboardProbe(changeCount: 0, types: [], duration: .zero)
        #expect(DiagnosticsReport.describe(probe) == "Änderungszähler 0, Formate: 0, 0.00 ms – keine")
    }
}

struct BuildEnvironmentTests {
    @Test(arguments: [
        ("1640", "16.4"),
        ("2600", "26.0"),
        ("2601", "26.0.1"),
        ("0941", "9.4.1"),
        ("16a", nil),
        ("12", nil),
    ] as [(String, String?)])
    func xcodeVersion(raw: String, expected: String?) {
        #expect(BuildEnvironment.xcodeVersion(raw) == expected)
    }

    @Test func describeCombinesKnownParts() {
        #expect(BuildEnvironment.describe(xcode: "1640", sdk: "macosx15.5") == "Xcode 16.4 · macosx15.5")
        #expect(BuildEnvironment.describe(xcode: nil, sdk: "macosx15.5") == "macosx15.5")
        #expect(BuildEnvironment.describe(xcode: nil, sdk: nil) == "unbekannt")
    }
}
