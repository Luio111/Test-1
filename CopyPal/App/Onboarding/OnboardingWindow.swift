import AppKit
import Observation
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// First start (ROADMAP M7): welcome, privacy promise, Accessibility, pasteboard
/// access, a practice field for holding ⌘V, start at login. Under 2 minutes.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private unowned let app: AppController
    private var window: NSWindow?
    private var model: OnboardingModel?

    init(app: AppController) {
        self.app = app
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        model?.startMonitoring()
        FocusReturn.remember()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stopMonitoring()
        FocusReturn.windowWillClose(window)
    }

    private func makeWindow() -> NSWindow {
        let model = OnboardingModel(app: app) { [weak self] in
            self?.window?.close()
        }
        self.model = model
        let controller = NSHostingController(rootView: OnboardingView(model: model, loginItem: app.loginItem))
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Willkommen bei CopyPal")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.Colors.windowBackground
        window.isReleasedWhenClosed = false
        // As large as SwiftUI lays out the view (as high as the tallest step), set before
        // centering: with the macOS 15+ SDK the hosting view sizes its window lazily.
        window.setContentSize(controller.view.fittingSize)
        window.center()
        window.delegate = self
        return window
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, privacy, accessibility, pasteboard, practice, screenshot, finish
}

@MainActor
@Observable
final class OnboardingModel {
    var step: OnboardingStep = .welcome
    private(set) var accessibility: PermissionState = AccessibilityPermission.state
    private(set) var pasteboardAccess: PasteboardAccessStatus = PasteboardInspector.accessStatus()
    private(set) var screenCapture: PermissionState = ScreenCapturePermission.state
    /// The system prompt for Screen Recording comes once; afterwards only System Settings.
    private(set) var screenCaptureAsked = AppSettings.screenshotPermissionAsked
    var practiceText = ""
    private(set) var samplesCopied = false

    @ObservationIgnored private unowned let app: AppController
    @ObservationIgnored private let onFinish: () -> Void
    @ObservationIgnored private var timer: Timer?

    static let samples = [
        String(localized: "Erster Beispieltext aus CopyPal"),
        String(localized: "Zweiter Beispieltext – halte ⌘V und drücke 2"),
        String(localized: "Dritter Beispieltext"),
    ]

    init(app: AppController, onFinish: @escaping () -> Void) {
        self.app = app
        self.onFinish = onFinish
    }

    var practiceSucceeded: Bool {
        Self.samples.contains { practiceText.contains($0) }
    }

    func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        accessibility = AccessibilityPermission.state
        pasteboardAccess = PasteboardInspector.accessStatus()
        screenCapture = ScreenCapturePermission.state
    }

    /// The screenshot shortcut as the menu bar writes it (⌘⇧A unless changed).
    var screenshotShortcut: String {
        KeyboardLayout.displayString(for: AppSettings.screenshotHotKey)
    }

    func requestScreenCapture() {
        app.screenshot.requestPermission()
        screenCaptureAsked = true
        refresh()
    }

    func openScreenCaptureSettings() {
        app.screenshot.openSystemSettings()
    }

    func next() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        } else {
            finish()
        }
    }

    func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    func requestAccessibility() {
        app.requestAccessibility()
        refresh()
    }

    func openPasteboardSettings() {
        app.openPasteboardPrivacySettings()
    }

    /// Copies three short texts one after the other, so the history has something to show.
    func copySamples() {
        Task {
            for sample in Self.samples.reversed() {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(sample, forType: .string)
                try? await Task.sleep(for: .milliseconds(600))
            }
            samplesCopied = true
        }
    }

    func finish() {
        AppSettings.hasCompletedOnboarding = true
        stopMonitoring()
        onFinish()
    }
}

struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let loginItem: LoginItem

    static let width: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Every step is laid out, the inactive ones hidden: the window fits the
            // tallest step and keeps its size while you click through.
            ZStack(alignment: .topLeading) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    if step == model.step {
                        content(for: step)
                    } else {
                        content(for: step)
                            .hidden()
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
            .padding(.top, Theme.Layout.pageTopPadding)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            Hairline()
            footer
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.Colors.background)
    }

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome: welcome
        case .privacy: privacy
        case .accessibility: accessibility
        case .pasteboard: pasteboard
        case .practice: practice
        case .screenshot: screenshot
        case .finish: finish
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            PageHeader(systemImage: "doc.on.clipboard", title: "Willkommen bei CopyPal", subtitle: "Dein Verlauf der Zwischenablage – ohne neue Tastenkombinationen.")
            explanationRow("command", title: "⌘C kopiert wie immer", text: "CopyPal merkt sich, was du kopierst.")
            explanationRow("hand.tap", title: "⌘V kurz drücken fügt ein", text: "Genau wie bisher: der zuletzt kopierte Eintrag.")
            explanationRow("rectangle.topthird.inset.filled", title: "⌘V halten öffnet den Verlauf", text: "An der Notch erscheinen deine letzten 8 Einträge. Eine Zahl von 1 bis 8 fügt den Eintrag ein, mit ⇧ ohne Formatierung.")
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            PageHeader(systemImage: "lock.shield", title: "Deine Daten bleiben bei dir")
            explanationRow("lock", title: "Verschlüsselt auf diesem Mac", text: "Der Schlüssel liegt in deinem Schlüsselbund. Ohne ihn ist der Verlauf unlesbar.")
            explanationRow("wifi.slash", title: "Keine Cloud, keine Statistik", text: "Keine Konten, keine Nutzungsdaten. Ins Netz nur für Updates – und nur, wenn du zustimmst.")
            explanationRow("key", title: "Passwörter bleiben draußen", text: "Kopien aus Passwortmanagern und als geheim markierte Inhalte speichert CopyPal nie.")
            explanationRow("timer", title: "Sensibles verschwindet", text: "IBAN, Kartennummern, Schlüssel und Einmalcodes werden verdeckt und nach einer Minute gelöscht.")
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            PageHeader(
                systemImage: "accessibility",
                title: "Bedienungshilfen erlauben",
                subtitle: "Damit CopyPal erkennt, ob du ⌘V kurz drückst oder hältst, und den gewählten Eintrag einfügen kann. CopyPal liest dabei keine Tastatureingaben mit."
            )
            HStack(spacing: Theme.Spacing.m) {
                if model.accessibility == .granted {
                    StatusTag(text: "Erteilt", style: .green)
                    Text("Alles bereit.").font(Theme.Typography.body)
                } else {
                    StatusTag(text: "Noch nicht erteilt", style: .orange)
                    Button("Freigabe anfordern") { model.requestAccessibility() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            Text("Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → CopyPal einschalten. Diese Seite erkennt die Freigabe automatisch.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pasteboard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            PageHeader(
                systemImage: "doc.on.clipboard",
                title: "Zugriff auf die Zwischenablage",
                subtitle: "Ab macOS 15.4 fragt macOS, ob eine App die Zwischenablage lesen darf. Für CopyPal „Immer erlauben“ wählen, sonst erscheint bei jeder Kopie eine Rückfrage."
            )
            HStack(spacing: Theme.Spacing.m) {
                switch model.pasteboardAccess {
                case .alwaysAllow:
                    StatusTag(text: "Immer erlauben", style: .green)
                case .unavailable:
                    StatusTag(text: "Nicht nötig auf diesem macOS", style: .green)
                default:
                    StatusTag(text: "Noch nicht auf „Immer erlauben“", style: .orange)
                    Button("Systemeinstellungen öffnen") { model.openPasteboardSettings() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            PageHeader(systemImage: "keyboard", title: "Probier es aus", subtitle: "1. Beispiele kopieren · 2. ins Feld klicken · 3. ⌘V halten und 2 drücken.")
            HStack(spacing: Theme.Spacing.m) {
                Button(model.samplesCopied ? LocalizedStringKey("Beispiele kopiert ✓") : LocalizedStringKey("Drei Beispiele kopieren")) {
                    model.copySamples()
                }
                    .buttonStyle(SubtleButtonStyle())
                if model.practiceSucceeded {
                    StatusTag(text: "Geschafft!", style: .green)
                }
            }
            TextEditor(text: $model.practiceText)
                .font(Theme.Typography.body)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.s)
                .frame(height: 140)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .accessibilityLabel(Text("Übungsfeld"))
            if model.accessibility != .granted {
                Text("Ohne Bedienungshilfen öffnet ⌃⌥V den Verlauf; der Eintrag landet dann in der Zwischenablage.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var screenshot: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            PageHeader(
                systemImage: "camera.viewfinder",
                title: "Bildschirmfoto mit \(model.screenshotShortcut)",
                subtitle: "Das Bild landet sofort in der Zwischenablage und im Verlauf – bereit für ⌘V."
            )
            explanationRow("macwindow", title: "Klick nimmt ein Fenster oder einen Bereich auf", text: "Der Rahmen rastet dort ein, wo der Zeiger steht. Ziehen wählt frei, Esc bricht ab.")
            explanationRow("arrow.down.to.line", title: "↓ erweitert die Aufnahme", text: "CopyPal scrollt weiter und setzt alles zu einem Bild zusammen – auch, was unterhalb des sichtbaren Bereichs liegt.")
            HStack(spacing: Theme.Spacing.m) {
                Text("Bildschirmaufnahme").font(Theme.Typography.bodyMedium)
                if model.screenCapture == .granted {
                    StatusTag(text: "Erteilt", style: .green)
                    Text("Probier es aus: \(model.screenshotShortcut) drücken.").font(Theme.Typography.body)
                } else {
                    StatusTag(text: "Noch nicht erteilt", style: .orange)
                    if model.screenCaptureAsked {
                        Button("Systemeinstellungen öffnen") { model.openScreenCaptureSettings() }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Freigabe anfordern") { model.requestScreenCapture() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            Text("CopyPal nimmt nur auf, wenn du das Kürzel drückst – nie im Hintergrund. Die Freigabe geht auch später, beim ersten \(model.screenshotShortcut).")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            PageHeader(systemImage: "checkmark.circle", title: "Fertig", subtitle: "CopyPal läuft in der Menüleiste. Dort findest du Verlauf, Pause und Einstellungen – und die Tastenkürzel, sobald der Zeiger auf dem Symbol ruht.")
            LoginItemSetting(loginItem: loginItem, detail: "Empfohlen, damit dein Verlauf immer mitläuft.")
        }
    }

    private func explanationRow(_ symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typography.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
                Text(text).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.m) {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == model.step ? Theme.Colors.accent : Theme.Colors.divider)
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Schritt \(model.step.rawValue + 1) von \(OnboardingStep.allCases.count)"))
            Spacer()
            if model.step != .welcome {
                Button("Zurück") { model.back() }
                    .buttonStyle(SubtleButtonStyle())
            }
            Button {
                model.next()
            } label: {
                Text(verbatim: nextTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
        .padding(.vertical, Theme.Spacing.l)
    }

    private var nextTitle: String {
        switch model.step {
        case .accessibility where model.accessibility != .granted: String(localized: "Später")
        case .pasteboard where model.pasteboardAccess != .alwaysAllow && model.pasteboardAccess != .unavailable: String(localized: "Später")
        case .screenshot where model.screenCapture != .granted: String(localized: "Später")
        case .finish: String(localized: "Los geht’s")
        default: String(localized: "Weiter")
        }
    }
}
