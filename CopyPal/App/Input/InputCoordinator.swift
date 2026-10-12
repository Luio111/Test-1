import AppKit
import CopyPalCore
import CopyPalSystem

/// Keeps the ⌘V event tap healthy and tells the app when ⌘V was held: starts the tap
/// as soon as Accessibility is granted, removes it at once when the grant is revoked,
/// re-enables it after timeouts, recreates it after sleep or a user switch, and turns
/// the gesture off in apps on the "hold off" list.
@MainActor
final class InputCoordinator {
    let tap: EventTapController
    private(set) var layout: KeyboardLayout.Resolution
    private(set) var permission: PermissionState

    /// ⌘V was held past the threshold.
    var onHold: (() -> Void)?
    /// Accessibility was granted or revoked while running.
    var onPermissionChange: ((PermissionState) -> Void)?

    private var watchdog: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        layout = KeyboardLayout.resolvePasteKey()
        permission = AccessibilityPermission.state
        tap = EventTapController(holdThreshold: AppSettings.holdThreshold, pasteKeyCode: layout.pasteKeyCode)
        tap.onShowPopup = { [weak self] in
            self?.onHold?()
        }
    }

    var canPaste: Bool {
        permission == .granted
    }

    func start() {
        syncTapWithPermission()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncTapWithPermission()
            }
        }
        observe(DistributedNotificationCenter.default(), KeyboardLayout.selectionChangedNotification) { coordinator in
            coordinator.refreshLayout()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { coordinator in
                coordinator.restartTap()
            }
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { coordinator in
            coordinator.updateHoldForFrontmostApp()
        }
        updateHoldForFrontmostApp()
    }

    /// Re-reads the gesture settings (called when settings change).
    func applySettings() {
        tap.holdThreshold = AppSettings.holdThreshold
        syncTapWithPermission()
        updateHoldForFrontmostApp()
    }

    func popupDidClose() {
        tap.popupDidClose()
    }

    func popupDidAppear() {
        tap.diagnostics.markPopupVisible()
    }

    /// Starts the tap when permitted and wanted, removes it at once when not.
    private func syncTapWithPermission() {
        let state = AccessibilityPermission.state
        if state != permission {
            permission = state
            onPermissionChange?(state)
        }
        if state == .granted, AppSettings.holdGestureEnabled {
            if !tap.isRunning {
                tap.start()
            }
            tap.ensureEnabled()
        } else if tap.isRunning {
            tap.stop()
        }
    }

    private func restartTap() {
        tap.stop()
        syncTapWithPermission()
    }

    private func refreshLayout() {
        layout = KeyboardLayout.resolvePasteKey()
        tap.pasteKeyCode = layout.pasteKeyCode
    }

    private func updateHoldForFrontmostApp() {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        tap.holdEnabled = bundleID.map { !AppSettings.holdDisabledBundleIDs.contains($0) } ?? true
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ action: @escaping @MainActor @Sendable (InputCoordinator) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }
}
