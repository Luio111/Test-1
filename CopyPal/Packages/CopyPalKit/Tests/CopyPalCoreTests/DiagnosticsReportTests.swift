import Foundation
import Testing
@testable import CopyPalCore

struct DiagnosticsReportTests {
    private func snapshot(
        signing: SigningStatus = .developer(teamID: "ABCDE12345", certificate: "Apple Development: Test (XYZ)"),
        accessibility: PermissionState = .granted,
        access: PasteboardAccessStatus = .alwaysAllow,
        probe: PasteboardProbe? = nil
    ) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            appVersion: "0.1.0",
            buildNumber: "1",
            bundleIdentifier: "io.example.CopyPal.dev",
            osVersion: "Version 26.1 (Build 25B78)",
            signing: signing,
            accessibility: accessibility,
            pasteboardAccess: access,
            pasteboardProbe: probe,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func healthySetupHasNoWarnings() {
        let report = DiagnosticsReport.text(for: snapshot())
        #expect(report.contains("Team ABCDE12345 – Apple Development: Test (XYZ)"))
        #expect(report.contains("Bedienungshilfen: erteilt"))
        #expect(report.contains("Zwischenablage-Test: nicht ausgeführt"))
        #expect(report.contains("Zeitpunkt: 1970-01-01T00:00:00Z"))
        #expect(!report.contains("Hinweis:"))
    }

    @Test(arguments: [SigningStatus.adHoc, .unsigned, .unknown("x")])
    func unstableSignatureIsFlagged(signing: SigningStatus) {
        #expect(!signing.isStable)
        let warnings = DiagnosticsReport.warnings(for: snapshot(signing: signing))
        #expect(warnings.contains { $0.contains("Keine stabile Signatur") })
    }

    @Test func missingAccessibilityIsFlagged() {
        let warnings = DiagnosticsReport.warnings(for: snapshot(accessibility: .denied))
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("Bedienungshilfen"))
    }

    @Test(arguments: [
        (PasteboardAccessStatus.unavailable, false),
        (.alwaysAllow, false),
        (.systemDefault, true),
        (.ask, true),
        (.alwaysDeny, true),
        (.unknown(rawValue: 9), true),
    ])
    func pasteboardAccessWarning(access: PasteboardAccessStatus, warns: Bool) {
        #expect(access.mayInterruptCapture == warns)
        let warnings = DiagnosticsReport.warnings(for: snapshot(access: access))
        #expect(warnings.contains { $0.contains("Zwischenablage-Zugriff") } == warns)
    }

    @Test func probeListsTypesButNoContents() {
        let probe = PasteboardProbe(
            changeCount: 42,
            types: ["public.utf8-plain-text", "public.html"],
            duration: .microseconds(1_500)
        )
        let report = DiagnosticsReport.text(for: snapshot(probe: probe))
        #expect(report.contains("Zwischenablage-Test: changeCount 42, 2 Typen, 1.50 ms – public.utf8-plain-text, public.html"))
    }

    @Test func emptyPasteboardProbe() {
        let probe = PasteboardProbe(changeCount: 0, types: [], duration: .zero)
        #expect(DiagnosticsReport.describe(probe) == "changeCount 0, 0 Typen, 0.00 ms – keine")
    }
}
