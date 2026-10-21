import AppKit
import SwiftUI
import CopyPalCore
import CopyPalServices
import CopyPalSystem

/// Shows the popup at the notch of the screen the user works on, handles its keys
/// (ROADMAP §1.8) and pastes the chosen entry into the app that was in front when the
/// popup opened.
@MainActor
final class PopupController {
    /// Called after the popup closed (by choice, esc or losing focus).
    var onClose: (() -> Void)?
    /// Called when the popup could not be put on the user's Space; it is not open then.
    var onShowFailed: (() -> Void)?
    /// Called right after the popup became visible (latency measurement).
    var onVisible: (() -> Void)?

    let model: PopupModel
    private let visuals: ClipVisuals
    private let paster: PasteController
    private lazy var panel = makePanel()
    private let retract = NotchRetract()
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var targetProcessID: pid_t?
    private var screen: NSScreen?
    /// Where the pointer was when the popup opened: hovering selects a row only after
    /// the mouse really moved (it may rest just where the popup appears).
    private var mouseLocationAtOpen: CGPoint = .zero
    /// When the opening spring started (system uptime), nil while collapsed.
    private var openStartedAt: TimeInterval?
    private var noticeTask: Task<Void, Never>?

    init(history: HistoryModel, visuals: ClipVisuals, paster: PasteController, presentation: PresentationMode) {
        model = PopupModel(history: history, visuals: visuals, presentation: presentation)
        self.visuals = visuals
        self.paster = paster
        // Created now, so the first ⌘V hold does not pay for building the panels.
        _ = panel
        retract.prepare()
    }

    var isVisible: Bool {
        panel.isVisible
    }

    /// The panel is on the Space the user sees; false would mean an invisible popup.
    var isOnActiveSpace: Bool {
        panel.isOnActiveSpace
    }

    /// The window server lists the panel among the windows on screen (needs no
    /// Screen Recording permission: only numbers and bounds are read).
    var isOnScreen: Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let number = panel.windowNumber
        return windows.contains { ($0[kCGWindowNumber as String] as? Int) == number }
    }

    #if DEBUG
    /// Self-test: inside "Favoriten" beside the notch (AppKit coordinates), to click it
    /// like the user does. The switch ends at the right edge of the band.
    var favoritesSwitchPoint: CGPoint {
        let frame = panel.frame
        let layout = model.layout
        return CGPoint(
            x: frame.midX + layout.bodySize.width / 2 - PopupMetrics.wingPadding - 20,
            y: frame.maxY - layout.bandHeight / 2
        )
    }

    /// Self-test: whether screen sharing is asked to leave the popup out.
    var panelSharingType: NSWindow.SharingType {
        panel.sharingType
    }

    /// Self-test: compares the click with the level the popup had before.
    var panelLevel: NSWindow.Level {
        get { panel.level }
        set { panel.level = newValue }
    }
    #endif

    private var animates: Bool {
        AppSettings.animatePopup && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `targetProcessID`: the app to paste into (frontmost when ⌘V was held).
    func show(targetProcessID: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier) {
        guard !isVisible else { return }
        retract.cancel()
        self.targetProcessID = targetProcessID
        mouseLocationAtOpen = NSEvent.mouseLocation
        openStartedAt = nil
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
        panel.applyScreenSharingPreference()
        guard panel.orderFrontOnActiveSpace() else {
            // Better no popup than an invisible one that keeps the gesture and ⌘V hostage.
            Log.app.error("Pop-up liegt nicht auf dem aktiven Space – abgebrochen (auf dem Bildschirm: \(self.isOnScreen, privacy: .public))")
            panel.orderOut(nil)
            onShowFailed?()
            return
        }
        panel.makeKey()
        installMonitors()
        let entryCount = model.visibleItems.count
        announce(String(localized: "CopyPal-Verlauf, \(entryCount) Einträge"))

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
                self.openStartedAt = ProcessInfo.processInfo.systemUptime
                self.model.contentVisible = true
            }
        }
    }

    /// `retracting`: false skips the closing animation (the user is on another Space).
    func close(retracting: Bool = true) {
        guard isVisible else { return }
        removeMonitors()
        // The visible popup leaves at once (focus and the paste go back to the app);
        // a passive copy of the shape shrinks back into the notch.
        if retracting, animates, model.expanded {
            retract.play(
                from: visibleSilhouette(),
                to: model.layout.silhouette(expanded: false),
                panelSize: model.layout.panelSize,
                frame: panel.frame
            )
        }
        panel.orderOut(nil)
        openStartedAt = nil
        withoutAnimation {
            model.expanded = false
            model.contentVisible = false
        }
        onClose?()
    }

    /// The shape as it is on screen: while the opening spring still runs (e.g. ⌘V
    /// held and 3 pressed right away) somewhere between the notch and the popup.
    private func visibleSilhouette() -> NotchShape {
        let expanded = model.layout.silhouette(expanded: true)
        guard let openStartedAt else { return expanded }
        let elapsed = ProcessInfo.processInfo.systemUptime - openStartedAt
        let progress = PopupMotion.openSpring.value(target: 1.0, time: elapsed)
        let collapsed = model.layout.silhouette(expanded: false)
        var change = expanded.animatableData - collapsed.animatableData
        change.scale(by: progress)
        var shape = collapsed
        shape.animatableData = collapsed.animatableData + change
        return shape
    }

    /// A short confirmation in the footer ("Zu Favoriten hinzugefügt").
    private func showNotice(_ notice: PopupNotice) {
        switch notice {
        case .favoriteAdded: announce(String(localized: "Zu Favoriten hinzugefügt"))
        case .favoriteRemoved: announce(String(localized: "Aus Favoriten entfernt"))
        }
        noticeTask?.cancel()
        withAnimation(Theme.Motion.quick) {
            model.notice = notice
        }
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_600))
            guard !Task.isCancelled, let self else { return }
            withAnimation(Theme.Motion.quick) {
                self.model.notice = nil
            }
        }
    }

    /// "Verlauf" or "Favoriten" clicked beside the notch (same as ⇥).
    func showList(_ list: PopupList) {
        guard model.list != list else { return }
        model.list = list
        contentChanged()
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
        // The preview takes the room of a full list.
        let rows = model.previewing ? PopupMetrics.maxRows : model.visibleItems.count
        let layout = PopupLayout(anchor: NotchGeometry.anchor(on: metrics), rows: rows)
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
        if model.previewing {
            switch action {
            case .cancel, .clearQuery, .hidePreview:
                // Esc and ← leave the preview first.
                hidePreview()
                return
            case .insertText, .deleteBackward, .switchList:
                // Typing and ⇥ change the list: back to it.
                hidePreview()
            default:
                break
            }
        }
        switch action {
        case let .select(index, plainText):
            paste(at: index - 1, plainText: plainText)
        case let .confirm(plainText):
            paste(at: model.selectedIndex, plainText: plainText)
        case .moveUp:
            model.selectedIndex = max(model.selectedIndex - 1, 0)
            previewSelection()
            announceSelection()
        case .moveDown:
            model.selectedIndex = min(model.selectedIndex + 1, max(model.visibleItems.count - 1, 0))
            previewSelection()
            announceSelection()
        case .showPreview:
            showPreview()
        case .hidePreview:
            break
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
            let notice: PopupNotice = item.isPinned ? .favoriteRemoved : .favoriteAdded
            Task {
                await model.history.perform { try await $0.togglePin(id) }
                // Stay on the entry (it keeps its place in the history) and say what happened.
                model.selectedIndex = model.visibleItems.firstIndex { $0.id == id } ?? model.selectedIndex
                model.clampSelection()
                withAnimation(PopupMotion.resize) {
                    updateLayout()
                }
                showNotice(notice)
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

    // MARK: Preview

    /// → : the selected entry in full, in the same shape (not in presentation mode).
    private func showPreview() {
        guard !model.concealsContent, let item = model.selectedItem else {
            NSSound.beep()
            return
        }
        model.previewing = true
        loadPreview(for: item)
        withAnimation(PopupMotion.resize) {
            updateLayout()
        }
    }

    private func hidePreview() {
        guard model.previewing else { return }
        model.previewing = false
        withAnimation(PopupMotion.resize) {
            updateLayout()
        }
    }

    /// ↑/↓ while previewing: the preview follows the selection.
    private func previewSelection() {
        guard model.previewing, let item = model.selectedItem else { return }
        loadPreview(for: item)
    }

    /// Loads the text or a larger picture once per opening, off the main thread.
    /// Sensitive entries and iPhone placeholders load nothing: the preview shows their
    /// masked title only.
    private func loadPreview(for item: ClipItem) {
        guard model.previews[item.id] == nil, !item.isSensitive, !item.isRemotePlaceholder else { return }
        switch item.kind {
        case .text, .richText, .link, .image, .other:
            break
        case .color, .files:
            return
        }
        model.previews[item.id] = .loading
        let engine = model.history.engine
        let id = item.id
        let kind = item.kind
        Task {
            let loaded = await Self.loadPreview(id: id, kind: kind, engine: engine)
            let content: PopupPreviewContent = switch loaded {
            case let .text(text): .text(text)
            case let .imageData(data): NSImage(data: data).map(PopupPreviewContent.image) ?? .unavailable
            case .unavailable: .unavailable
            }
            self.model.previews[id] = content
        }
    }

    private enum LoadedPreview: Sendable {
        case text(String)
        case imageData(Data)
        case unavailable
    }

    nonisolated private static func loadPreview(id: UUID, kind: ClipKind, engine: HistoryEngine) async -> LoadedPreview {
        guard let representations = try? await engine.representations(of: id) else { return .unavailable }
        if kind == .image {
            guard let png = representations.first(where: { $0.type == PasteboardTypeID.png })?.data,
                  let data = ImageConversion.thumbnail(fromImageData: png, maxPixelSize: 960) else {
                return .unavailable
            }
            return .imageData(data)
        }
        guard let plain = representations.first(where: { $0.type == PasteboardTypeID.plainText }) else {
            return .unavailable
        }
        return .text(String(String(decoding: plain.data, as: UTF8.self).prefix(4_000)))
    }

    private func contentChanged() {
        model.selectedIndex = 0
        model.clampSelection()
        withAnimation(PopupMotion.resize) {
            updateLayout()
        }
        let resultCount = model.visibleItems.count
        if model.query.isEmpty {
            let listName = model.list == .favorites ? String(localized: "Favoriten") : String(localized: "Verlauf")
            announce(String(localized: "\(listName), \(resultCount) Einträge"))
        } else {
            announce(String(localized: "\(resultCount) Treffer"))
        }
    }

    // MARK: VoiceOver

    /// Tells VoiceOver users what changed; the popup never moves the VoiceOver cursor
    /// away from the app being pasted into.
    private func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: priority.rawValue]
        )
    }

    /// ↑/↓: number and title of the new row (the kind only in presentation mode).
    private func announceSelection() {
        guard let item = model.selectedItem else { return }
        let title = model.concealsContent ? visuals.kindLabel(for: item) : (visuals.favoriteName(for: item) ?? visuals.title(for: item))
        announce("\(model.selectedIndex + 1): \(title)", priority: .high)
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
        // Switching Spaces (swipe, full screen on/off) leaves the popup behind and
        // changes the app that would be pasted into: close.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close(retracting: false)
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
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
    }

    private func makePanel() -> PopupPanel {
        let view = PopupRootView(
            model: model,
            visuals: visuals,
            onSelect: { [weak self] index in self?.paste(at: index, plainText: false) },
            onHover: { [weak self] index in self?.hover(index) },
            onShowList: { [weak self] list in self?.showList(list) }
        )
        return PopupPanel(contentView: FirstClickHostingView(rootView: view))
    }
}

/// The closing animation: the black shape shrinks back into the notch in its own
/// panel, which never takes focus or clicks.
@MainActor
private final class NotchRetract {
    @MainActor
    @Observable
    final class Model {
        var shape = NotchShape(bodyWidth: 0, height: 0, bottomRadius: 0, flare: 0)
        var panelSize = CGSize.zero
    }

    private let model = Model()
    private lazy var panel = NotchRetractPanel(contentView: NSHostingView(rootView: NotchRetractView(model: model)))
    private var hideTask: Task<Void, Never>?

    /// Builds the panel ahead of time, off the path of the first ⌘V hold and close.
    func prepare() {
        _ = panel
    }

    func play(from start: NotchShape, to end: NotchShape, panelSize: CGSize, frame: CGRect) {
        hideTask?.cancel()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.shape = start
            model.panelSize = panelSize
        }
        panel.setFrame(frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.applyScreenSharingPreference()
        panel.orderFrontRegardless()
        hideTask = Task { @MainActor [weak self] in
            // About one frame later, so the start state is on screen before it shrinks.
            try? await Task.sleep(for: .seconds(PopupMotion.firstFrame))
            guard let self, !Task.isCancelled else { return }
            withAnimation(PopupMotion.close) {
                self.model.shape = end
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
        model.shape
            .fill(Theme.Notch.fill)
            .frame(width: model.panelSize.width, height: model.panelSize.height, alignment: .top)
    }
}
