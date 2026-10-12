import AppKit
import CopyPalCore
import CopyPalSystem

/// Wires the ⌘V event tap to the popup and keeps the tap healthy: starts it as soon
/// as Accessibility is granted, removes it immediately when the grant is revoked,
/// re-enables it after timeouts and recreates it after sleep or a user switch.
@MainActor
final class InputCoordinator {
    let tap: EventTapController
    let popup = PopupController()
    private(set) var layout: KeyboardLayout.Resolution

    private var watchdog: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        layout = KeyboardLayout.resolvePasteKey()
        tap = EventTapController(holdThreshold: AppSettings.holdThreshold, pasteKeyCode: layout.pasteKeyCode)

        tap.onShowPopup = { [weak self] in
            self?.popup.show()
        }
        popup.onClose = { [weak self] in
            self?.tap.popupDidClose()
        }
        popup.onVisible = { [weak self] in
            self?.tap.diagnostics.markPopupVisible()
        }
        popup.pasteKeyCode = { [weak self] in
            self?.layout.pasteKeyCode ?? KeyboardLayout.fallbackPasteKeyCode
        }
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
    }

    func setHoldThreshold(_ seconds: Double) {
        AppSettings.holdThreshold = seconds
        tap.holdThreshold = AppSettings.holdThreshold
    }

    /// Starts the tap when permitted, removes it at once when not.
    private func syncTapWithPermission() {
        if AccessibilityPermission.state == .granted {
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
