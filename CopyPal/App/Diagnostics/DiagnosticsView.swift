import SwiftUI
import CopyPalCore

struct DiagnosticsView: View {
    let model: DiagnosticsModel

    private var snapshot: DiagnosticsSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                if !callouts.isEmpty {
                    callout
                }
                appSection
                Hairline()
                permissionsSection
                Hairline()
                pasteboardSection
                Hairline()
                footer
            }
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .frame(minWidth: 580, minHeight: 540)
        .background(Theme.Colors.background)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: "stethoscope")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, Theme.Spacing.xs)
            Text("Diagnose")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Technische Angaben für Fehlerberichte. Enthält keine Inhalte deiner Zwischenablage.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: Callout

    private var callouts: [LocalizedStringKey] {
        var result: [LocalizedStringKey] = []
        if !snapshot.signing.isStable {
            result.append("Die App ist nicht stabil signiert. Die Freigabe für Bedienungshilfen geht dadurch bei jedem Build verloren – siehe Docs/Troubleshooting.md.")
        }
        if snapshot.accessibility == .denied {
            result.append("Bedienungshilfen sind nicht freigegeben. Ohne sie kann CopyPal ⌘V nicht erkennen.")
        }
        if snapshot.pasteboardAccess.mayInterruptCapture {
            result.append("Der Zugriff auf die Zwischenablage steht nicht auf „Immer erlauben“. macOS kann beim Mitlesen nachfragen.")
        }
        return result
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Tag.orange.foreground)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(Array(callouts.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }

    // MARK: Sections

    private var appSection: some View {
        SectionBlock(title: "App") {
            PropertyRow(label: "Version", systemImage: "number") {
                Text(verbatim: "\(snapshot.appVersion) (\(snapshot.buildNumber))")
            }
            PropertyRow(label: "Bundle-ID", systemImage: "shippingbox") {
                Text(verbatim: snapshot.bundleIdentifier).font(Theme.Typography.mono)
            }
            PropertyRow(label: "macOS", systemImage: "laptopcomputer") {
                Text(verbatim: snapshot.osVersion)
            }
            PropertyRow(label: "Signatur", systemImage: "signature") {
                signingValue
            }
        }
    }

    @ViewBuilder
    private var signingValue: some View {
        switch snapshot.signing {
        case let .developer(teamID, certificate):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    StatusTag(text: "Stabil", style: .green)
                    Text(verbatim: teamID).font(Theme.Typography.mono)
                }
                if let certificate {
                    Text(verbatim: certificate)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        case .adHoc:
            StatusTag(text: "Ad hoc – nicht stabil", style: .red)
        case .unsigned:
            StatusTag(text: "Unsigniert", style: .red)
        case let .unknown(reason):
            HStack(spacing: Theme.Spacing.s) {
                StatusTag(text: "Unbekannt", style: .gray)
                Text(verbatim: reason).font(Theme.Typography.mono)
            }
        }
    }

    private var permissionsSection: some View {
        SectionBlock(title: "Berechtigungen") {
            PropertyRow(label: "Bedienungshilfen", systemImage: "accessibility") {
                HStack(spacing: Theme.Spacing.s) {
                    if snapshot.accessibility == .granted {
                        StatusTag(text: "Erteilt", style: .green)
                    } else {
                        StatusTag(text: "Nicht erteilt", style: .red)
                        Button("Anfragen") { model.requestAccessibility() }
                            .buttonStyle(SubtleButtonStyle())
                        Button("Einstellungen öffnen") { model.openAccessibilitySettings() }
                            .buttonStyle(SubtleButtonStyle())
                    }
                }
            }
        }
    }

    private var pasteboardSection: some View {
        SectionBlock(title: "Zwischenablage") {
            PropertyRow(label: "Zugriff durch Apps", systemImage: "lock") {
                pasteboardAccessTag
            }
            PropertyRow(label: "Lesetest", systemImage: "doc.on.clipboard") {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Button("Jetzt testen") { model.runPasteboardProbe() }
                        .buttonStyle(SubtleButtonStyle())
                    if let probe = snapshot.pasteboardProbe {
                        probeResult(probe)
                    } else {
                        Text("Liest nur Änderungszähler und Formate. Achte darauf, ob macOS dabei einen Hinweis zeigt.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pasteboardAccessTag: some View {
        switch snapshot.pasteboardAccess {
        case .alwaysAllow: StatusTag(text: "Immer erlauben", style: .green)
        case .ask: StatusTag(text: "Fragen", style: .orange)
        case .systemDefault: StatusTag(text: "Systemstandard", style: .orange)
        case .alwaysDeny: StatusTag(text: "Nie erlauben", style: .red)
        case .unavailable: StatusTag(text: "Nicht vorhanden (vor macOS 15.4)", style: .gray)
        case let .unknown(rawValue): StatusTag(text: "Unbekannt (\(rawValue))", style: .gray)
        }
    }

    private func probeResult(_ probe: PasteboardProbe) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("\(probe.types.count) Formate · Zähler \(probe.changeCount) · \(DiagnosticsReport.milliseconds(probe.duration)) ms")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            if !probe.types.isEmpty {
                Text(verbatim: probe.types.joined(separator: "\n"))
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Den Bericht kannst du in einen GitHub-Kommentar einfügen.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
            Button {
                model.copyReport()
            } label: {
                model.reportCopied ? Text("Kopiert ✓") : Text("Bericht kopieren")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}
