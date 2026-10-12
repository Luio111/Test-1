import Observation
import ServiceManagement
import SwiftUI

/// "Start at login" through `SMAppService` (ROADMAP M7), including the case where
/// macOS wants the user to approve it in System Settings.
@MainActor
@Observable
final class LoginItem {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but the user has to allow it in System Settings → Login Items.
        case requiresApproval
    }

    private(set) var state: State = .disabled
    /// Why the last change did not take effect, shown below the switch.
    private(set) var lastError: String?

    init() {
        refresh()
    }

    /// The switch shows "on" while macOS waits for the user's approval, too.
    var isOn: Bool {
        state != .disabled
    }

    func refresh() {
        state = switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        // macOS also reports `.notFound` for an app that was never registered (e.g. a
        // fresh build), so registering is still worth a try.
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        refresh()
        if enabled, state == .disabled, lastError == nil {
            lastError = String(localized: "macOS hat den Anmeldestart nicht übernommen.")
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// The "start at login" switch with approval hint and error, for settings and onboarding.
struct LoginItemSetting: View {
    let loginItem: LoginItem
    /// Shown while nothing needs the user's attention.
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SettingRow(title: "Bei der Anmeldung starten", detail: currentDetail) {
                Toggle("", isOn: Binding(
                    get: { loginItem.isOn },
                    set: { loginItem.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if let error = loginItem.lastError {
                Label {
                    Text(verbatim: error)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            if loginItem.state == .requiresApproval || loginItem.lastError != nil {
                Button("Anmeldeobjekte öffnen …") { loginItem.openSystemSettings() }
                    .buttonStyle(SubtleButtonStyle())
            }
        }
        .onAppear { loginItem.refresh() }
    }

    private var currentDetail: LocalizedStringKey {
        loginItem.state == .requiresApproval
            ? "macOS wartet auf deine Zustimmung unter Systemeinstellungen → Allgemein → Anmeldeobjekte."
            : detail
    }
}
