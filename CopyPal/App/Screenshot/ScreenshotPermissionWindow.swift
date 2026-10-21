import AppKit
import Observation
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// Asks for Screen Recording the first time a screenshot is taken (ROADMAP M11,
/// onboarding style). Watches the permission while open and confirms it with
/// ScreenCaptureKit, which also tells whether a relaunch is needed.
@MainActor
final class ScreenshotPermissionWindowController: NSObject, NSWindowDelegate {
    private unowned let controller: ScreenshotController
    private var window: NSWindow?
    private var model: ScreenshotPermissionModel?

    init(controller: ScreenshotController) {
        self.controller = controller
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        model?.startMonitoring()
        FocusReturn.remember()
        NSApp.activate()
        // ⌘⇧A may come from a full-screen app: the window opens on that Space, in front
        // even if macOS does not let CopyPal become active.
        window.orderFrontOnActiveSpace()
        window.makeKey()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model?.stopMonitoring()
        FocusReturn.windowWillClose(window)
        controller.permissionWindowDidClose()
    }

    private func makeWindow() -> NSWindow {
        let model = ScreenshotPermissionModel(controller: controller) { [weak self] in
            self?.window?.close()
        }
        self.model = model
        let hosting = NSHostingController(rootView: ScreenshotPermissionView(model: model))
        let window = EscapeClosingWindow(contentViewController: hosting)
        window.title = String(localized: "Bildschirmaufnahme erlauben")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.Colors.windowBackground
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.delegate = self
        return window
    }
}

/// Esc closes it like „Später“, also when no button has the focus.
final class EscapeClosingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
@Observable
final class ScreenshotPermissionModel {
    private(set) var state: PermissionState = ScreenCapturePermission.state
    /// What ScreenCaptureKit said once the preflight turned green.
    private(set) var verified: ScreenCapturePermission.VerifiedState?
    private(set) var asked = AppSettings.screenshotPermissionAsked

    @ObservationIgnored private unowned let controller: ScreenshotController
    @ObservationIgnored private let onFinish: () -> Void
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var verifying = false

    init(controller: ScreenshotController, onFinish: @escaping () -> Void) {
        self.controller = controller
        self.onFinish = onFinish
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        refresh()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func request() {
        controller.requestPermission()
        asked = true
        refresh()
    }

    func openSystemSettings() {
        controller.openSystemSettings()
    }

    func relaunch() {
        controller.relaunch()
    }

    func later() {
        onFinish()
    }

    func changeShortcut() {
        onFinish()
        controller.openShortcutSettings()
    }

    /// The shortcut that opened this window, as the menu bar writes it.
    var shortcutText: String {
        KeyboardLayout.displayString(for: AppSettings.screenshotHotKey)
    }

    private func refresh() {
        let current = ScreenCapturePermission.state
        if current != state {
            state = current
            if current == .denied { verified = nil }
        }
        if current == .granted, verified != .granted, !verifying {
            verify()
        }
    }

    /// The preflight says yes; ScreenCaptureKit decides whether this process has it.
    private func verify() {
        verifying = true
        Task { [weak self] in
            let result = await ScreenCapturePermission.verify()
            guard let self else { return }
            self.verifying = false
            guard result != self.verified else { return }
            self.verified = result
            switch result {
            case .granted:
                Self.announce(String(localized: "Bildschirmaufnahme erteilt"))
                // The capture starts once this window is gone (see the controller).
                self.controller.permissionWindowDidVerify()
                try? await Task.sleep(for: .milliseconds(800))
                self.onFinish()
            case .needsRelaunch:
                Self.announce(String(localized: "macOS übernimmt die Freigabe erst nach einem Neustart von CopyPal."))
            case .denied, .failed:
                break
            }
        }
    }

    private static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

struct ScreenshotPermissionView: View {
    let model: ScreenshotPermissionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                PageHeader(
                    systemImage: "camera.viewfinder",
                    title: "Bildschirmaufnahme erlauben",
                    subtitle: "Für Bildschirmfotos braucht CopyPal die Freigabe „Bildschirmaufnahme“. CopyPal nimmt nur auf, wenn du das Tastenkürzel drückst – nie im Hintergrund. Im Verlauf werden Bildschirmfotos verschlüsselt gespeichert; wie jede Kopie kann macOS sie per Universal Clipboard an dein iPhone oder iPad geben."
                )
                HStack(spacing: Theme.Spacing.m) {
                    status
                }
                caption
            }
            .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
            .padding(.top, Theme.Layout.pageTopPadding)
            .padding(.bottom, Theme.Spacing.xl)

            Hairline()

            HStack(spacing: Theme.Spacing.s) {
                Text("Geöffnet mit \(model.shortcutText)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button("Kürzel ändern …") { model.changeShortcut() }
                    .buttonStyle(SubtleButtonStyle())
                Spacer()
                Button("Später") { model.later() }
                    .buttonStyle(SubtleButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
            .padding(.vertical, Theme.Spacing.l)
        }
        .frame(width: 560)
        .background(Theme.Colors.background)
    }

    @ViewBuilder
    private var status: some View {
        switch (model.state, model.verified) {
        case (.granted, .granted):
            StatusTag(text: "Erteilt", style: .green)
            Text("Alles bereit.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        case (.granted, .needsRelaunch):
            StatusTag(text: "Erteilt", style: .green)
            Button("CopyPal neu starten") { model.relaunch() }
                .buttonStyle(PrimaryButtonStyle())
        case (.granted, .failed):
            StatusTag(text: "Prüfung fehlgeschlagen", style: .orange)
        case (.granted, _):
            StatusTag(text: "Erteilt", style: .green)
        default:
            StatusTag(text: "Noch nicht erteilt", style: .orange)
            if model.asked {
                Button("Systemeinstellungen öffnen") { model.openSystemSettings() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Freigabe anfordern") { model.request() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            switch model.verified {
            case .needsRelaunch:
                Text("macOS übernimmt die Freigabe erst nach einem Neustart von CopyPal.")
            case let .failed(message):
                Text("Prüfung fehlgeschlagen: \(message)")
            default:
                Text("Systemeinstellungen → Datenschutz & Sicherheit → Bildschirmaufnahme → CopyPal einschalten. Dieses Fenster erkennt die Freigabe automatisch.")
            }
            Text("macOS 15 fragt etwa einmal im Monat erneut nach – das ist normal.")
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
