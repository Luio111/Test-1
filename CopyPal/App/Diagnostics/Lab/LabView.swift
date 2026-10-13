#if DEBUG
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// Debug-only measuring window for milestone M1 (ROADMAP M1 / Testplan M1).
struct LabView: View {
    @Bindable var model: LabModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                statusSection
                Hairline()
                settingsSection
                Hairline()
                measurementsSection
                Hairline()
                eventsSection
                Hairline()
                pasteboardSection
                Hairline()
                footer
            }
            .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
            .padding(.top, Theme.Layout.pageTopPadding)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .frame(minWidth: 620, minHeight: 640)
        .background(Theme.Colors.background)
        .onChange(of: model.holdThreshold) { model.applyHoldThreshold() }
        .onChange(of: model.pasteDelay) { model.applyPasteDelay() }
        .onChange(of: model.remoteMode) { model.applyRemoteMode() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: "flask")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, Theme.Spacing.xs)
                .accessibilityHidden(true)
            Text("Labor")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Messwerte für ⌘V halten und das Mitlesen der Zwischenablage. Nur im Debug-Build; erfasst Tastencodes und Formate – keine Zeichen, keine Inhalte.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var statusSection: some View {
        SectionBlock(title: "Status") {
            PropertyRow(label: "Event-Tap", systemImage: "keyboard") {
                if model.tapRunning && model.tapEnabled {
                    StatusTag(text: "Läuft", style: .green)
                } else if model.tapRunning {
                    StatusTag(text: "Pausiert", style: .orange)
                } else {
                    StatusTag(text: "Aus", style: .red)
                }
            }
            PropertyRow(label: "Bedienungshilfen", systemImage: "accessibility") {
                StatusTag(text: model.accessibility == .granted ? "Erteilt" : "Nicht erteilt",
                          style: model.accessibility == .granted ? .green : .red)
            }
            PropertyRow(label: "Sichere Eingabe", systemImage: "lock.shield") {
                if model.secureInput.isEnabled {
                    HStack(spacing: Theme.Spacing.s) {
                        StatusTag(text: "Aktiv", style: .orange)
                        Text(verbatim: model.secureInput.appName ?? "unbekannte App")
                    }
                } else {
                    StatusTag(text: "Aus", style: .gray)
                }
            }
            PropertyRow(label: "Notch", systemImage: "rectangle.topthird.inset.filled") {
                Button(model.notchOverlayVisible ? "Overlay ausblenden" : "Berechnete Notch zeigen") {
                    model.toggleNotchOverlay()
                }
                .buttonStyle(SubtleButtonStyle())
            }
            PropertyRow(label: "Tastaturlayout", systemImage: "globe") {
                Text(verbatim: "\(model.layout.layoutName) · ⌘V-Taste \(model.layout.pasteKeyCode)\(model.layout.resolved ? "" : " (Standard)")")
            }
        }
    }

    private var settingsSection: some View {
        SectionBlock(title: "Einstellungen") {
            PropertyRow(label: "Halteschwelle", systemImage: "timer") {
                HStack(spacing: Theme.Spacing.m) {
                    Slider(value: $model.holdThreshold, in: AppSettings.holdThresholdRange, step: 0.05)
                    Text(verbatim: String(format: "%.2f s", model.holdThreshold))
                        .font(Theme.Typography.mono)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            PropertyRow(label: "Wartezeit vor Einfügen", systemImage: "hourglass") {
                HStack(spacing: Theme.Spacing.m) {
                    Slider(value: $model.pasteDelay, in: AppSettings.pasteDelayRange, step: 10)
                    Text(verbatim: String(format: "%.0f ms", model.pasteDelay))
                        .font(Theme.Typography.mono)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    private var measurementsSection: some View {
        SectionBlock(title: "Messwerte") {
            PropertyRow(label: "Tipp-Dauer", systemImage: "hand.tap") {
                summary(model.snapshot.tap)
            }
            PropertyRow(label: "Pop-up-Latenz", systemImage: "rectangle.portrait.and.arrow.forward") {
                summary(model.snapshot.popup)
            }
            PropertyRow(label: "Längster Callback", systemImage: "speedometer") {
                Text(verbatim: String(format: "%.2f ms", model.snapshot.slowestCallback))
                    .font(Theme.Typography.mono)
            }
        }
    }

    private func summary(_ value: LatencySummary?) -> some View {
        Group {
            if let value {
                Text(verbatim: String(format: "Median %.0f ms · p90 %.0f ms · max %.0f ms · n = %ld", value.median, value.p90, value.max, value.count))
                    .font(Theme.Typography.mono)
            } else {
                Text("Noch keine Messung")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var eventsSection: some View {
        SectionBlock(title: "Letzte Ereignisse") {
            if model.snapshot.entries.isEmpty {
                Text("Drücke oder halte ⌘V in einer beliebigen App.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    ForEach(model.snapshot.entries.suffix(12).reversed()) { entry in
                        Text(verbatim: LabModel.describe(entry))
                            .font(Theme.Typography.mono)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private var pasteboardSection: some View {
        SectionBlock(title: "Zwischenablage (M2)") {
            PropertyRow(label: "iPhone-Kopien", systemImage: "iphone") {
                Picker(selection: $model.remoteMode) {
                    Text("Erst bei Auswahl laden").tag(RemoteClipboardMode.onDemand)
                    Text("Sofort lesen").tag(RemoteClipboardMode.readImmediately)
                    Text("Nur Typen (ignorieren)").tag(RemoteClipboardMode.ignore)
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .frame(width: 220)
            }
            PropertyRow(label: "Schreibtest", systemImage: "square.and.pencil") {
                HStack(spacing: Theme.Spacing.s) {
                    Button("Normal schreiben") { model.writeTest(localOnly: false) }
                        .buttonStyle(SubtleButtonStyle())
                    Button("Nur lokal schreiben") { model.writeTest(localOnly: true) }
                        .buttonStyle(SubtleButtonStyle())
                }
            }
            PropertyRow(label: "Verlauf", systemImage: "internaldrive") {
                Text(verbatim: "\(model.historyCount) Einträge · \(model.diskUsage / 1024) KB")
            }
            if model.captureLog.isEmpty {
                Text("Kopiere etwas mit ⌘C – jede Änderung erscheint hier mit Formaten, Quell-App, Größe und Lesedauer.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    ForEach(model.captureLog.suffix(12).reversed()) { entry in
                        Text(verbatim: LabModel.describe(entry))
                            .font(Theme.Typography.mono)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button("Messwerte zurücksetzen") { model.resetMeasurements() }
                .buttonStyle(SubtleButtonStyle())
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
#endif
