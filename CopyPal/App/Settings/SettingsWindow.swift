import AppKit
import SwiftUI
import CopyPalCore
import CopyPalSystem

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let app: AppController
    private var window: NSWindow?

    init(app: AppController) {
        self.app = app
    }

    func show(page: SettingsPage = .general) {
        let window = window ?? makeWindow(page: page)
        self.window = window
        app.loginItem.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(page: SettingsPage) -> NSWindow {
        let view = SettingsView(app: app, settings: SettingsModel(), loginItem: app.loginItem, history: app.history, initialPage: page)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = String(localized: "Einstellungen")
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.Colors.windowBackground
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 780, height: 640))
        window.center()
        window.delegate = self
        return window
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, history, privacy, favorites, about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "Allgemein"
        case .history: "Verlauf"
        case .privacy: "Datenschutz"
        case .favorites: "Favoriten"
        case .about: "Über"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .history: "clock.arrow.circlepath"
        case .privacy: "lock.shield"
        case .favorites: "pin"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    let app: AppController
    @Bindable var settings: SettingsModel
    let loginItem: LoginItem
    let history: HistoryModel
    @State private var page: SettingsPage

    init(app: AppController, settings: SettingsModel, loginItem: LoginItem, history: HistoryModel, initialPage: SettingsPage) {
        self.app = app
        self.settings = settings
        self.loginItem = loginItem
        self.history = history
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.Colors.divider).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    switch page {
                    case .general: GeneralSettings(app: app, settings: settings, loginItem: loginItem)
                    case .history: HistorySettings(app: app, settings: settings)
                    case .privacy: PrivacySettingsPage(app: app, settings: settings)
                    case .favorites: FavoritesSettings(history: history)
                    case .about: AboutPage(updates: app.updates, settings: settings)
                    }
                }
                .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
                .padding(.top, Theme.Layout.pageTopPadding)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .background(Theme.Colors.background)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPage.allCases) { item in
                Button {
                    page = item
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: item.systemImage)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(item.title)
                        Spacer()
                    }
                    .font(Theme.Typography.body)
                    .foregroundStyle(page == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.s)
                    .frame(height: 28)
                    .background(page == item ? Theme.Colors.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == item ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.top, Theme.Layout.pageTopPadding)
        .padding(.horizontal, Theme.Spacing.s)
        .frame(width: 180)
        .background(Theme.Colors.surface)
    }
}

// MARK: General

private struct GeneralSettings: View {
    let app: AppController
    @Bindable var settings: SettingsModel
    let loginItem: LoginItem

    var body: some View {
        PageHeader(systemImage: "gearshape", title: "Allgemein", subtitle: "⌘V kurz drücken fügt wie gewohnt ein. ⌘V halten öffnet den Verlauf an der Notch.")

        SectionBlock(title: "⌘V halten") {
            SettingRow(title: "⌘V halten öffnet den Verlauf", detail: "Aus: ⌘V bleibt völlig unverändert, der Verlauf öffnet sich nur mit dem Tastenkürzel.") {
                Toggle("", isOn: $settings.holdGestureEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Halteschwelle", detail: "So lange musst du ⌘V halten. Kürzer wirkt schneller, länger verhindert Versehen.") {
                HStack(spacing: Theme.Spacing.m) {
                    Slider(value: $settings.holdThreshold, in: AppSettings.holdThresholdRange, step: 0.05)
                        .frame(width: 160)
                    Text(verbatim: String(format: "%.2f s", settings.holdThreshold))
                        .font(Theme.Typography.mono)
                        .frame(width: 52, alignment: .trailing)
                }
                .disabled(!settings.holdGestureEnabled)
            }
            SettingRow(title: "Apps ohne ⌘V halten", detail: "In diesen Apps kommt ⌘V immer unverändert an (z. B. virtuelle Maschinen, Fernzugriff).") {
                Button("Bearbeiten …") { editingHoldOff = true }
                    .buttonStyle(SubtleButtonStyle())
            }
        }
        .sheet(isPresented: $editingHoldOff) {
            AppListEditor(
                title: "Apps ohne ⌘V halten",
                bundleIDs: $settings.holdDisabledBundleIDs,
                defaults: HoldOffList.defaultBundleIDs,
                settings: settings
            )
        }

        Hairline()

        SectionBlock(title: "Tastenkürzel") {
            SettingRow(title: "Verlauf mit Tastenkürzel öffnen", detail: "Funktioniert auch ohne Bedienungshilfen-Freigabe.") {
                Toggle("", isOn: $settings.hotKeyEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Tastenkürzel") {
                HotKeyRecorder(shortcut: $settings.hotKey)
                    .disabled(!settings.hotKeyEnabled)
            }
        }

        Hairline()

        SectionBlock(title: "Darstellung") {
            SettingRow(title: "Animation aus der Notch", detail: "Folgt automatisch „Bewegung reduzieren“ in den Bedienungshilfen.") {
                Toggle("", isOn: $settings.animatePopup).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "„Kopiert“ an der Notch zeigen") {
                Toggle("", isOn: $settings.showCopyFeedback).labelsHidden().toggleStyle(.switch)
            }
        }

        Hairline()

        SectionBlock(title: "Start") {
            SettingRow(title: "Bei der Anmeldung starten", detail: loginDetail) {
                Toggle("", isOn: Binding(
                    get: { loginItem.state == .enabled || loginItem.state == .requiresApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(loginItem.state == .unavailable)
            }
            if loginItem.state == .requiresApproval {
                Button("Anmeldeobjekte öffnen …") { loginItem.openSystemSettings() }
                    .buttonStyle(SubtleButtonStyle())
            }
        }
    }

    @State private var editingHoldOff = false

    private var loginDetail: LocalizedStringKey {
        switch loginItem.state {
        case .requiresApproval: "macOS wartet auf deine Zustimmung unter Systemeinstellungen → Allgemein → Anmeldeobjekte."
        case .unavailable: "Nur verfügbar, wenn CopyPal im Programme-Ordner liegt."
        case .enabled, .disabled: "CopyPal startet unsichtbar in der Menüleiste."
        }
    }
}

/// Click, then press the new combination (with ⌘, ⌥ or ⌃). Esc cancels.
private struct HotKeyRecorder: View {
    @Binding var shortcut: HotKeyShortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Group {
                if recording {
                    Text("Tasten drücken …")
                } else {
                    Text(verbatim: KeyboardLayout.displayString(for: shortcut))
                }
            }
            .font(Theme.Typography.mono)
            .frame(minWidth: 110)
        }
        .buttonStyle(SubtleButtonStyle())
        .accessibilityLabel(Text("Tastenkürzel: \(KeyboardLayout.displayString(for: shortcut))"))
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = KeyModifiers(event.modifierFlags)
            MainActor.assumeIsolated {
                if keyCode == 53 { // esc
                    stop()
                    return
                }
                let candidate = HotKeyShortcut(keyCode: keyCode, modifiers: modifiers.intersection([.command, .option, .control, .shift]))
                if candidate.isValid {
                    shortcut = candidate
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = false
    }
}

// MARK: History

private struct HistorySettings: View {
    let app: AppController
    @Bindable var settings: SettingsModel

    var body: some View {
        PageHeader(systemImage: "clock.arrow.circlepath", title: "Verlauf", subtitle: "Favoriten sind von allen Grenzen ausgenommen.")

        SectionBlock(title: "Umfang") {
            SettingRow(title: "Einträge im Verlauf", detail: "Ältere Einträge werden automatisch gelöscht.") {
                Picker("", selection: $settings.historyLimit) {
                    ForEach(AppSettings.historyLimitOptions, id: \.self) { value in
                        Text(verbatim: "\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            SettingRow(title: "Aufbewahren", detail: "Einträge, die so lange nicht benutzt wurden, verschwinden.") {
                Picker("", selection: $settings.retentionDays) {
                    ForEach(AppSettings.retentionDayOptions, id: \.self) { days in
                        Text(Self.retentionLabel(days)).tag(days)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
        }

        Hairline()

        SectionBlock(title: "iPhone (Universelle Zwischenablage)") {
            SettingRow(title: "Kopien vom iPhone", detail: remoteDetail) {
                Picker("", selection: $settings.remoteClipboardMode) {
                    Text("Erst bei Auswahl laden").tag(RemoteClipboardMode.onDemand)
                    Text("Sofort übernehmen").tag(RemoteClipboardMode.readImmediately)
                    Text("Ignorieren").tag(RemoteClipboardMode.ignore)
                }
                .labelsHidden()
                .frame(width: 200)
            }
        }

        Hairline()

        SectionBlock(title: "Vorschauen") {
            SettingRow(title: "Website-Symbole laden", detail: "Lädt das Symbol einer kopierten Website aus dem Netz. Aus: CopyPal stellt nie eine Verbindung her.") {
                Toggle("", isOn: $settings.loadFavicons).labelsHidden().toggleStyle(.switch)
            }
        }

        Hairline()

        SectionBlock(title: "Verlauf löschen") {
            SettingRow(title: "Alle Einträge löschen", detail: "Favoriten bleiben erhalten.") {
                Button("Verlauf löschen …") { app.confirmClearHistory() }
                    .buttonStyle(SubtleButtonStyle())
            }
        }
    }

    private var remoteDetail: LocalizedStringKey {
        switch settings.remoteClipboardMode {
        case .onDemand: "Erscheint sofort im Verlauf; den Inhalt holt CopyPal erst, wenn du ihn auswählst – so zeigt macOS „Einfügen vom iPhone“ nur dann."
        case .readImmediately: "Wird wie eine Kopie am Mac gespeichert. macOS kann dabei kurz „Einfügen vom iPhone“ anzeigen."
        case .ignore: "Kopien vom iPhone erscheinen nicht im Verlauf."
        }
    }

    static func retentionLabel(_ days: Int) -> LocalizedStringKey {
        switch days {
        case 0: "Unbegrenzt"
        case 1: "1 Tag"
        case 7: "1 Woche"
        case 30: "30 Tage"
        case 90: "90 Tage"
        case 365: "1 Jahr"
        default: "\(days) Tage"
        }
    }
}

// MARK: Privacy

private struct PrivacySettingsPage: View {
    let app: AppController
    @Bindable var settings: SettingsModel
    @State private var editingIgnore = false

    var body: some View {
        PageHeader(
            systemImage: "lock.shield",
            title: "Datenschutz",
            subtitle: "Alles bleibt verschlüsselt auf diesem Mac. CopyPal sammelt keine Nutzungsdaten und geht nur für Updates und Website-Symbole ins Netz – beides nur mit deiner Zustimmung."
        )

        SectionBlock(title: "Sensible Inhalte") {
            SettingRow(title: "Sensible Einträge löschen nach", detail: "IBAN, Kartennummern, API-Schlüssel und Einmalcodes werden verdeckt angezeigt, sind nicht durchsuchbar und gehen nie ans iPhone.") {
                Picker("", selection: $settings.sensitiveLifetimeSeconds) {
                    ForEach(AppSettings.sensitiveLifetimeOptions, id: \.self) { seconds in
                        Text(Self.lifetimeLabel(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            SettingRow(title: "Einmalcodes erkennen", detail: "Sechsstellige Zahlen wie „123 456“ gelten als sensibel.") {
                Toggle("", isOn: $settings.detectOneTimeCodes).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Zwischenablage danach leeren", detail: "Liegt ein sensibler Eintrag beim Ablauf noch in der Zwischenablage, wird sie geleert.") {
                Toggle("", isOn: $settings.clearPasteboardAfterSensitive).labelsHidden().toggleStyle(.switch)
            }
        }

        Hairline()

        SectionBlock(title: "Ignorierte Apps") {
            SettingRow(title: "Kopien aus diesen Apps nie speichern", detail: "Voreingestellt: Passwortmanager, Schlüsselbund, Passwörter-App, Banking.") {
                Button("Bearbeiten …") { editingIgnore = true }
                    .buttonStyle(SubtleButtonStyle())
            }
        }
        .sheet(isPresented: $editingIgnore) {
            IgnoreListEditor(settings: settings)
        }

        Hairline()

        SectionBlock(title: "Aufzeichnung") {
            SettingRow(title: pauseTitle, detail: "Während der Pause speichert CopyPal nichts. Das Menüleisten-Symbol zeigt die Pause.") {
                if app.capture.isPaused || settings.pausedUntil != nil {
                    Button("Fortsetzen") { app.resumeCapture() }
                        .buttonStyle(SubtleButtonStyle())
                } else {
                    Menu("Pausieren") {
                        Button("15 Minuten") { app.pauseCapture(for: 15 * 60) }
                        Button("1 Stunde") { app.pauseCapture(for: 3_600) }
                        Button("Bis zur Reaktivierung") { app.pauseCapture(for: nil) }
                    }
                    .fixedSize()
                }
            }
        }
    }

    private var pauseTitle: LocalizedStringKey {
        app.capture.isPaused ? "Aufzeichnung pausiert" : "Aufzeichnung läuft"
    }

    static func lifetimeLabel(_ seconds: Int) -> LocalizedStringKey {
        switch seconds {
        case 30: "30 Sekunden"
        case 60: "1 Minute"
        case 300: "5 Minuten"
        case 900: "15 Minuten"
        default: "\(seconds) Sekunden"
        }
    }
}

private struct IgnoreListEditor: View {
    @Bindable var settings: SettingsModel
    @Environment(\.dismiss) private var dismiss

    private var entries: [String] {
        DefaultIgnoreList.entries.map(\.bundleID) + settings.customIgnoredBundleIDs.filter { !DefaultIgnoreList.bundleIDs.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Ignorierte Apps")
                .font(Theme.Typography.bodyMedium)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries, id: \.self) { bundleID in
                        Toggle(isOn: Binding(get: { settings.isIgnored(bundleID) }, set: { settings.setIgnored(bundleID, $0) })) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: settings.displayName(for: bundleID)).font(Theme.Typography.body)
                                Text(verbatim: bundleID).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
            .frame(height: 280)
            HStack {
                Button("App hinzufügen …") {
                    if let bundleID = settings.chooseApp() {
                        settings.setIgnored(bundleID, true)
                    }
                }
                .buttonStyle(SubtleButtonStyle())
                Button("Standard wiederherstellen") { settings.restoreDefaultIgnoreList() }
                    .buttonStyle(SubtleButtonStyle())
                Spacer()
                Button("Fertig") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 480)
        .background(Theme.Colors.background)
    }
}

/// Simple list editor for bundle IDs with defaults (used for "hold off" apps).
private struct AppListEditor: View {
    let title: LocalizedStringKey
    @Binding var bundleIDs: [String]
    let defaults: [String]
    let settings: SettingsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.Typography.bodyMedium)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(bundleIDs, id: \.self) { bundleID in
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: settings.displayName(for: bundleID)).font(Theme.Typography.body)
                                Text(verbatim: bundleID).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Button {
                                bundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Entfernen"))
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
            .frame(height: 260)
            HStack {
                Button("App hinzufügen …") {
                    if let bundleID = settings.chooseApp(), !bundleIDs.contains(bundleID) {
                        bundleIDs.append(bundleID)
                    }
                }
                .buttonStyle(SubtleButtonStyle())
                Button("Standard wiederherstellen") { bundleIDs = defaults }
                    .buttonStyle(SubtleButtonStyle())
                Spacer()
                Button("Fertig") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 480)
        .background(Theme.Colors.background)
    }
}

// MARK: Favorites

private struct FavoritesSettings: View {
    let history: HistoryModel
    @State private var labels: [UUID: String] = [:]

    var body: some View {
        PageHeader(systemImage: "pin", title: "Favoriten", subtitle: "Benennen, sortieren, löschen. Favoriten überstehen „Verlauf löschen“ und jede Aufbewahrungsfrist.")

        if history.favorites.isEmpty {
            Text("Noch keine Favoriten. Im Pop-up macht ⌘P den ausgewählten Eintrag zum Favoriten.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(history.favorites.enumerated()), id: \.element.id) { index, item in
                    FavoriteRow(
                        item: item,
                        label: Binding(get: { labels[item.id] ?? item.pinLabel ?? "" }, set: { labels[item.id] = $0 }),
                        canMoveUp: index > 0,
                        canMoveDown: index < history.favorites.count - 1,
                        onCommit: { save(item) },
                        onMove: { move(item, by: $0) },
                        onDelete: { remove(item) }
                    )
                    Hairline()
                }
            }
        }
    }

    private func save(_ item: ClipItem) {
        let label = (labels[item.id] ?? "").trimmingCharacters(in: .whitespaces)
        let id = item.id
        Task { await history.perform { try await $0.setPinLabel(id, label: label.isEmpty ? nil : label) } }
    }

    private func move(_ item: ClipItem, by offset: Int) {
        var ids = history.favorites.map(\.id)
        guard let index = ids.firstIndex(of: item.id) else { return }
        let target = index + offset
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        let ordered = ids
        Task { await history.perform { try await $0.reorderFavorites(ordered) } }
    }

    private func remove(_ item: ClipItem) {
        let id = item.id
        Task { await history.perform { try await $0.togglePin(id) } }
    }
}

private struct FavoriteRow: View {
    let item: ClipItem
    @Binding var label: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onCommit: () -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name (optional)", text: $label)
                    .onSubmit(onCommit)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.bodyMedium)
                Text(verbatim: item.displayTitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { onMove(-1) } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .accessibilityLabel(Text("Nach oben"))
            Button { onMove(1) } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .accessibilityLabel(Text("Nach unten"))
            Button(action: onDelete) { Image(systemName: "pin.slash") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Aus Favoriten entfernen"))
        }
        .padding(.vertical, Theme.Spacing.s)
    }
}

// MARK: About

private struct AboutPage: View {
    let updates: UpdateController
    @Bindable var settings: SettingsModel

    var body: some View {
        PageHeader(systemImage: "doc.on.clipboard", title: "CopyPal", subtitle: "Der Verlauf deiner Zwischenablage – mit ⌘V.")

        SectionBlock(title: "Version") {
            PropertyRow(label: "Version") {
                Text(verbatim: "\(AppInfo.version) (\(AppInfo.build))")
            }
            PropertyRow(label: "Gebaut mit") {
                Text(verbatim: AppInfo.buildEnvironment)
            }
            if updates.isAvailable {
                SettingRow(title: "Beta-Versionen erhalten", detail: "Neue Funktionen früher – mit kleinem Risiko.") {
                    Toggle("", isOn: $settings.betaUpdates).labelsHidden().toggleStyle(.switch)
                }
                Button("Nach Updates suchen …") { updates.checkForUpdates() }
                    .buttonStyle(SubtleButtonStyle())
            }
        }

        Hairline()

        SectionBlock(title: "Datenschutzversprechen") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label("Alles bleibt auf diesem Mac, verschlüsselt mit einem Schlüssel aus deinem Schlüsselbund.", systemImage: "lock")
                Label("Keine Konten, keine Cloud, keine Nutzungsstatistik, keine Werbung. Ins Netz geht CopyPal nur für Updates und Website-Symbole – beides nur, wenn du es erlaubst.", systemImage: "eye.slash")
                Label("Passwortmanager und markierte Inhalte werden nie gespeichert.", systemImage: "key")
                Label("Sensible Einträge verschwinden nach kurzer Zeit und gehen nie ans iPhone.", systemImage: "timer")
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
        }

        Hairline()

        SectionBlock(title: "Open Source") {
            Text("CopyPal verwendet GRDB (MIT-Lizenz) und Sparkle (MIT-Lizenz); swift-crypto (Apache 2.0) nur für Tests.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
