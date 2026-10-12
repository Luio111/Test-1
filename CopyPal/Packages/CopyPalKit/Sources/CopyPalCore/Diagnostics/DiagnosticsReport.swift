import Foundation

/// Plain-text diagnostics report that users paste into PR comments or issues.
/// Deliberately not localized: it is a stable technical artifact. Never contains
/// clipboard contents, only pasteboard type identifiers.
public enum DiagnosticsReport {
    public static func text(for snapshot: DiagnosticsSnapshot) -> String {
        var lines = [
            "CopyPal Diagnose",
            "Zeitpunkt: \(timestamp(snapshot.createdAt))",
            "App: \(snapshot.appVersion) (\(snapshot.buildNumber))",
            "Bundle-ID: \(snapshot.bundleIdentifier)",
            "macOS: \(snapshot.osVersion)",
            "Signatur: \(describe(snapshot.signing))",
            "Bedienungshilfen: \(describe(snapshot.accessibility))",
            "Zwischenablage-Zugriff: \(describe(snapshot.pasteboardAccess))",
        ]
        if let probe = snapshot.pasteboardProbe {
            lines.append("Zwischenablage-Test: \(describe(probe))")
        } else {
            lines.append("Zwischenablage-Test: nicht ausgeführt")
        }

        let warnings = warnings(for: snapshot)
        if !warnings.isEmpty {
            lines.append("")
            lines.append(contentsOf: warnings.map { "Hinweis: \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    public static func warnings(for snapshot: DiagnosticsSnapshot) -> [String] {
        var result: [String] = []
        if !snapshot.signing.isStable {
            result.append("Keine stabile Signatur – die Bedienungshilfen-Freigabe geht bei jedem Build verloren (siehe Docs/Troubleshooting.md).")
        }
        if snapshot.accessibility == .denied {
            result.append("Bedienungshilfen nicht freigegeben – ⌘V kann nicht abgefangen werden.")
        }
        if snapshot.pasteboardAccess.mayInterruptCapture {
            result.append("Zwischenablage-Zugriff steht nicht auf „Immer erlauben“ – macOS kann beim Mitlesen nachfragen oder blockieren.")
        }
        return result
    }

    static func describe(_ signing: SigningStatus) -> String {
        switch signing {
        case let .developer(teamID, certificate):
            if let certificate { return "Team \(teamID) – \(certificate)" }
            return "Team \(teamID)"
        case .adHoc: return "ad hoc (nicht stabil)"
        case .unsigned: return "unsigniert"
        case let .unknown(reason): return "unbekannt (\(reason))"
        }
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
        case .systemDefault: "Systemstandard"
        case .ask: "fragen"
        case .alwaysAllow: "immer erlauben"
        case .alwaysDeny: "nie erlauben"
        case let .unknown(rawValue): "unbekannt (\(rawValue))"
        }
    }

    static func describe(_ probe: PasteboardProbe) -> String {
        let types = probe.types.isEmpty ? "keine" : probe.types.joined(separator: ", ")
        return "changeCount \(probe.changeCount), \(probe.types.count) Typen, \(milliseconds(probe.duration)) ms – \(types)"
    }

    public static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let ms = Double(seconds) * 1_000 + Double(attoseconds) / 1e15
        return String(format: "%.2f", ms)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
