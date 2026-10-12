import AppKit
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// Shows the popup at the notch of the screen the user works on, handles its keys
/// (ROADMAP §1.8) and pastes the chosen entry into the app that was in front when the
/// popup opened.
@MainActor
final class PopupController {
    /// Called after the popup closed (by choice, esc or losing focus).
    var onClose: (() -> Void)?
    /// Called right after the popup became visible (latency measurement).
    var onVisible: (() -> Void)?

    let model: PopupModel
    private let visuals: ClipVisuals
    private let paster: PasteController
    private lazy var panel = makePanel()
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var targetProcessID: pid_t?
    private var screen: NSScreen?

    init(history: HistoryModel, visuals: ClipVisuals, paster: PasteController) {
        model = PopupModel(history: history)
        self.visuals = visuals
        self.paster = paster
        // Created now, so the first ⌘V hold does not pay for building the panel.
        _ = panel
    }

    var isVisible: Bool {
        panel.isVisible
    }

    /// `targetProcessID`: the app to paste into (frontmost when ⌘V was held).
    func show(targetProcessID: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier) {
        guard !isVisible else { return }
        self.targetProcessID = targetProcessID
        model.reset()
        screen = FocusedWindow.screenForPopup(frontmostProcessID: targetProcessID) ?? NSScreen.main ?? NSScreen.screens.first
        updateLayout()

        let animate = AppSettings.animatePopup && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.expanded = !animate
        model.contentVisible = !animate
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
        if animate {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                model.expanded = true
            }
            withAnimation(.easeOut(duration: 0.14).delay(0.1)) {
                model.contentVisible = true
            }
        }

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

    // MARK: Layout

    /// Card below the notch (or menu bar); the panel reaches up to the top of the
    /// screen so the grow animation can start at the notch itself.
    private func updateLayout() {
        guard let screen else { return }
        let metrics = ScreenMetrics(screen)
        let cardSize = CGSize(width: PopupMetrics.width, height: PopupMetrics.cardHeight(rows: model.visibleItems.count))
        let card = NotchGeometry.popupFrame(size: cardSize, on: metrics)
        let panelFrame = CGRect(x: card.minX, y: card.minY, width: card.width, height: max(metrics.frame.maxY - card.minY, card.height))
        let cardTop = panelFrame.maxY - card.maxY

        let start: CGSize
        let startTop: CGFloat
        if let notch = NotchGeometry.notchRect(on: metrics) {
            start = notch.size
            startTop = panelFrame.maxY - notch.maxY
        } else {
            start = CGSize(width: 120, height: 10)
            startTop = cardTop
        }
        model.layout = PopupLayout(
            panelSize: panelFrame.size,
            cardTop: cardTop,
            cardSize: cardSize,
            startSize: start,
            startTop: startTop,
            startRadius: start.height / 2
        )
        panel.setFrame(panelFrame, display: true)
    }

    // MARK: Keys

    /// The parts of a key event the popup needs (plain values, safe to hand around).
    struct KeyPress: Sendable {
        var keyCode: UInt16
        var modifiers: KeyModifiers
        var characters: String?
        var baseCharacters: String?

        init(_ event: NSEvent) {
            keyCode = event.keyCode
            modifiers = KeyModifiers(event.modifierFlags)
            characters = event.characters
            baseCharacters = event.charactersIgnoringModifiers
        }
    }

    func handleKey(_ press: KeyPress) {
        let action = PopupKeyMap.action(
            keyCode: press.keyCode,
            modifiers: press.modifiers,
            characters: press.characters,
            baseCharacters: press.baseCharacters,
            queryIsEmpty: model.query.isEmpty
        )
        guard let action else { return }
        switch action {
        case let .select(index, plainText):
            paste(at: index - 1, plainText: plainText)
        case let .confirm(plainText):
            paste(at: model.selectedIndex, plainText: plainText)
        case .moveUp:
            model.selectedIndex = max(model.selectedIndex - 1, 0)
        case .moveDown:
            model.selectedIndex = min(model.selectedIndex + 1, max(model.visibleItems.count - 1, 0))
        case .cancel:
            close()
        case .clearQuery:
            model.query = ""
            contentChanged()
        case let .insertText(text):
            model.query += text
            contentChanged()
        case .deleteBackward:
            if !model.query.isEmpty {
                model.query.removeLast()
            }
            contentChanged()
        case .switchList:
            model.list = model.list == .history ? .favorites : .history
            contentChanged()
        case .togglePin:
            guard let item = model.selectedItem else { return NSSound.beep() }
            let id = item.id
            Task {
                await model.history.perform { try await $0.togglePin(id) }
                contentChanged()
            }
        case .deleteItem:
            guard let item = model.selectedItem else { return NSSound.beep() }
            let id = item.id
            Task {
                await model.history.perform { try await $0.delete([id]) }
                contentChanged()
            }
        }
    }

    private func contentChanged() {
        model.selectedIndex = 0
        model.clampSelection()
        updateLayout()
    }

    private func paste(at index: Int, plainText: Bool) {
        let items = model.visibleItems
        guard items.indices.contains(index) else {
            NSSound.beep()
            return
        }
        let item = items[index]
        let target = targetProcessID
        close()
        Task {
            await paster.paste(item, plainText: plainText, targetProcessID: target)
        }
    }

    // MARK: Monitors

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let press = KeyPress(event)
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.handleKey(press)
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
        let view = PopupRootView(model: model, visuals: visuals) { [weak self] index in
            self?.paste(at: index, plainText: false)
        }
        return PopupPanel(contentView: NSHostingView(rootView: view))
    }
}
