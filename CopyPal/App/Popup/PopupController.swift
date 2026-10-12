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
    private let retract = NotchRetract()
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var targetProcessID: pid_t?
    private var screen: NSScreen?
    /// Where the pointer was when the popup opened: hovering selects a row only after
    /// the mouse really moved (it may rest just where the popup appears).
    private var mouseLocationAtOpen: CGPoint = .zero

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

    private var animates: Bool {
        AppSettings.animatePopup && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `targetProcessID`: the app to paste into (frontmost when ⌘V was held).
    func show(targetProcessID: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier) {
        guard !isVisible else { return }
        retract.cancel()
        self.targetProcessID = targetProcessID
        mouseLocationAtOpen = NSEvent.mouseLocation
        model.reset()
        screen = FocusedWindow.screenForPopup(frontmostProcessID: targetProcessID) ?? NSScreen.main ?? NSScreen.screens.first
        let animate = animates

        // Start collapsed in the notch (hidden behind the camera housing) and let the
        // hosting view draw that state before the panel appears, so every opening
        // animates from the notch.
        withoutAnimation {
            updateLayout()
            model.expanded = !animate
            model.contentVisible = !animate
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onVisible?()
            }
        }
        guard animate else { return }
        // About one frame later, so the collapsed state has been drawn and SwiftUI
        // animates from it. It is invisible: behind the camera housing, or zero high.
        DispatchQueue.main.asyncAfter(deadline: .now() + PopupMotion.firstFrame) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, !self.model.expanded else { return }
                withAnimation(PopupMotion.open) {
                    self.model.expanded = true
                }
                self.model.contentVisible = true
            }
        }
    }

    func close() {
        guard isVisible else { return }
        removeMonitors()
        // The visible popup leaves at once (focus and the paste go back to the app);
        // a passive copy of the shape shrinks back into the notch.
        if animates, model.expanded {
            retract.play(layout: model.layout, frame: panel.frame)
        }
        panel.orderOut(nil)
        withoutAnimation {
            model.expanded = false
            model.contentVisible = false
        }
        onClose?()
    }

    /// The mouse moved onto row `index`: select it, so ⌘P, ⌘⌫ and ↩ act on it.
    func hover(_ index: Int) {
        guard NSEvent.mouseLocation != mouseLocationAtOpen else { return }
        model.selectedIndex = index
    }

    // MARK: Layout

    /// The panel hangs from the top edge, centered on the notch, as large as the
    /// tallest popup; only the shape inside changes with the number of rows.
    private func updateLayout() {
        guard let screen else { return }
        let metrics = ScreenMetrics(screen)
        let layout = PopupLayout(anchor: NotchGeometry.anchor(on: metrics), rows: model.visibleItems.count)
        model.layout = layout
        let frame = NotchGeometry.popupPanelFrame(size: layout.panelSize, on: metrics)
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
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
        withAnimation(PopupMotion.resize) {
            updateLayout()
        }
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
        let view = PopupRootView(
            model: model,
            visuals: visuals,
            onSelect: { [weak self] index in self?.paste(at: index, plainText: false) },
            onHover: { [weak self] index in self?.hover(index) }
        )
        return PopupPanel(contentView: NSHostingView(rootView: view))
    }
}

/// The closing animation: the black shape shrinks back into the notch in its own
/// panel, which never takes focus or clicks.
@MainActor
private final class NotchRetract {
    @MainActor
    @Observable
    final class Model {
        var layout = PopupLayout.zero
        var expanded = true
    }

    private let model = Model()
    private lazy var panel = NotchRetractPanel(contentView: NSHostingView(rootView: NotchRetractView(model: model)))
    private var hideTask: Task<Void, Never>?

    func play(layout: PopupLayout, frame: CGRect) {
        hideTask?.cancel()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.layout = layout
            model.expanded = true
        }
        panel.setFrame(frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        hideTask = Task { @MainActor [weak self] in
            // About one frame later, so the expanded state is on screen before it shrinks.
            try? await Task.sleep(for: .seconds(PopupMotion.firstFrame))
            guard let self, !Task.isCancelled else { return }
            withAnimation(PopupMotion.close) {
                self.model.expanded = false
            }
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
        }
    }

    func cancel() {
        hideTask?.cancel()
        hideTask = nil
        panel.orderOut(nil)
    }
}

private struct NotchRetractView: View {
    let model: NotchRetract.Model

    var body: some View {
        model.layout.silhouette(expanded: model.expanded)
            .fill(Theme.Notch.fill)
            .frame(width: model.layout.panelSize.width, height: model.layout.panelSize.height, alignment: .top)
    }
}
