import AppKit
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// Shows the popup below the notch, handles its keys and pastes the chosen entry
/// into the app that was frontmost when the popup opened.
@MainActor
final class PopupController {
    /// Called after the popup closed (by choice, esc or losing focus).
    var onClose: (() -> Void)?
    /// Called right after the popup became visible (latency measurement).
    var onVisible: (() -> Void)?
    /// Current key code of ⌘V's "v" (it depends on the keyboard layout).
    var pasteKeyCode: () -> UInt16 = { KeyboardLayout.fallbackPasteKeyCode }

    private let model = PopupModel()
    private lazy var panel = makePanel()
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var targetProcessID: pid_t?

    var isVisible: Bool {
        panel.isVisible
    }

    func show() {
        guard !isVisible else { return }
        targetProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        model.selectedIndex = 0

        // NSScreen.main is the screen with the keyboard focus, i.e. the target app's window.
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let size = panel.contentView?.fittingSize ?? CGSize(width: PopupView.width, height: 320)
            panel.setFrame(NotchGeometry.popupFrame(size: size, on: ScreenMetrics(screen)), display: true)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        installMonitors()

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onVisible?()
            }
        }
    }

    func close() {
        guard isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        onClose?()
    }

    // MARK: Keys

    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let action = PopupKeyMap.action(keyCode: keyCode, modifiers: KeyModifiers(flags)) else {
            return // Typing to search arrives in M4; until then other keys are ignored.
        }
        switch action {
        case let .select(index, plainText):
            paste(at: index - 1, plainText: plainText)
        case let .confirm(plainText):
            paste(at: model.selectedIndex, plainText: plainText)
        case .moveUp:
            model.selectedIndex = max(model.selectedIndex - 1, 0)
        case .moveDown:
            model.selectedIndex = min(model.selectedIndex + 1, model.items.count - 1)
        case .cancel:
            close()
        }
    }

    private func paste(at index: Int, plainText: Bool) {
        guard model.items.indices.contains(index) else { return }
        let clip = model.items[index]
        let target = targetProcessID
        close()
        clip.write(to: .general, plainText: plainText)

        // Give focus a moment to return to the target app, then paste only if it is
        // still in front; otherwise the entry just stays on the clipboard.
        let delay = Duration.milliseconds(Int(AppSettings.pasteDelayMilliseconds))
        let keyCode = pasteKeyCode()
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else {
                NSSound.beep()
                return
            }
            PasteSynthesizer.postPaste(keyCode: keyCode)
        }
    }

    // MARK: Monitors

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            MainActor.assumeIsolated {
                self?.handleKey(keyCode: keyCode, flags: flags)
            }
            return nil
        }
        // Clicking anywhere else or switching apps takes the key status away: close.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
    }

    private func makePanel() -> PopupPanel {
        let view = PopupView(model: model) { [weak self] index in
            self?.paste(at: index, plainText: false)
        }
        return PopupPanel(contentView: NSHostingView(rootView: view))
    }
}
