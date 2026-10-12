import Foundation
import Observation
import ServiceManagement

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
        /// Not available (e.g. the app runs from a disk image or build folder).
        case unavailable
    }

    private(set) var state: State = .disabled
    private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        state = switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
