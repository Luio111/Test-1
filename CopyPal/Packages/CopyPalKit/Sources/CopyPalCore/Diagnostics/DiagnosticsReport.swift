import Foundation

/// Plain-text diagnostics report that users paste into PR comments or issues.
/// Deliberately not localized: it is a stable technical artifact. Contains no
/// clipboard contents and no personal data (only the team ID, not the name or
/// Apple ID from the signing certificate).
public enum DiagnosticsReport {
    public static func text(for snapshot: DiagnosticsSnapshot) -> String {
        var lines = [
            "CopyPal Diagnose",
            "Zeitpunkt: \(timestamp(snapshot.createdAt))",
            "App: \(snapshot.appVersion) (\(snapshot.buildNumber))",
            "Bundle-ID: \(snapshot.bundleIdentifier)",
            "Gebaut mit: \(snapshot.buildEnvironment)",
            "macOS: \(snapshot.osVersion)",
            "Signatur: \(describe(snapshot.signing))",
            "Bedienungshilfen: \(describe(snapshot.accessibility))",
            "Bildschirmaufnahme: \(snapshot.screenCapture.map(describe) ?? "– (Bildschirmfoto aus)")",
            "Zugriff auf Zwischenablage: \(describe(snapshot.pasteboardAccess))",
            "Lesetest: \(snapshot.pasteboardProbe.map(describe) ?? "nicht ausgeführt")",
        ]

        let warnings = DiagnosticsWarning.warnings(for: snapshot)
        if !warnings.isEmpty {
            lines.append("")
            lines.append(contentsOf: warnings.map { "Hinweis: \(text(for: $0))" })
        }
        return lines.joined(separator: "\n")
    }

    static func text(for warning: DiagnosticsWarning) -> String {
        switch warning {
        case .unstableSigning:
            "Keine stabile Signatur – die Bedienungshilfen-Freigabe geht bei jedem Build verloren (siehe Docs/Troubleshooting.md)."
        case .accessibilityDenied:
            "Bedienungshilfen nicht freigegeben – ⌘V kann nicht abgefangen werden."
        case .pasteboardMayAsk:
            "Zugriff auf die Zwischenablage steht nicht auf „Immer erlauben“ – macOS kann beim Mitlesen nachfragen."
        case .pasteboardDenied:
            "Zugriff auf die Zwischenablage ist verboten – CopyPal kann nichts mitlesen."
        case .pasteboardStatusUnknown:
            "Zugriff auf die Zwischenablage nicht auslesbar – App mit Xcode 16.3 oder neuer bauen."
        case .screenCaptureDenied:
            "Bildschirmaufnahme nicht erteilt – Bildschirmfotos sind nicht möglich."
        }
    }

    static func describe(_ signing: SigningStatus) -> String {
        switch signing {
        case let .developer(teamID, certificate):
            // Only the certificate kind ("Apple Development"), never the holder's name or e-mail.
            if let kind = certificate.flatMap(certificateKind) { return "Team \(teamID) – \(kind)" }
            return "Team \(teamID)"
        case .adHoc: return "ad hoc (nicht stabil)"
        case .unsigned: return "unsigniert"
        case let .unknown(reason): return "unbekannt (\(reason))"
        }
    }

    /// "Apple Development: Jane Doe (ABC123)" → "Apple Development"
    static func certificateKind(_ summary: String) -> String? {
        guard let kind = summary.split(separator: ":", maxSplits: 1).first, summary.contains(":") else {
            return nil
        }
        return kind.trimmingCharacters(in: .whitespaces)
    }

    static func describe(_ permission: PermissionState) -> String {
        switch permission {
        case .granted: "erteilt"
        case .denied: "nicht erteilt"
        }
    }

    static func describe(_ access: PasteboardAccessStatus) -> String {
        switch access {
        case .unavailable: "nicht vorhanden (vor macOS 15.4)"
        case .notInBuildSDK: "nicht auslesbar (mit SDK vor macOS 15.4 gebaut)"
        case .systemDefault: "Systemstandard"
        case .ask: "fragen"
        case .alwaysAllow: "immer erlauben"
        case .alwaysDeny: "nie erlauben"
        case let .unknown(rawValue): "unbekannt (\(rawValue))"
        }
    }

    static func describe(_ probe: PasteboardProbe) -> String {
        let types = probe.types.isEmpty ? "keine" : probe.types.joined(separator: ", ")
        let ms = String(format: "%.2f", probe.milliseconds)
        return "Änderungszähler \(probe.changeCount), Formate: \(probe.types.count), \(ms) ms – \(types)"
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
