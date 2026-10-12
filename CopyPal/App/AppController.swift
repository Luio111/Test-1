import AppKit
import CopyPalCore
import CopyPalServices
import CopyPalStorage
import CopyPalSystem

/// Composition root: owns the history, capture, paste, popup, hotkey, menu bar and
/// windows, and applies settings changes at once.
@MainActor
final class AppController {
    static let isSelfTest = CommandLine.arguments.contains("--self-test")

    /// System time plus the debug "time + N days" offset (ROADMAP M5).
    let timeSource: OffsetTimeSource
    let engine: HistoryEngine
    let history: HistoryModel
    let visuals: ClipVisuals
    let capture: CaptureCoordinator
    let input: InputCoordinator
    let toast: ToastController
    let paster: PasteController
    let popup: PopupController
    let hotKey = GlobalHotKey()
    let loginItem = LoginItem()
    /// Where the history lives; for the self-test a temporary folder.
    let storageDirectory: URL
    /// Set when the history could not be opened normally (shown in the menu).
    private(set) var storageProblem: String?
    /// The self-test reopens the store with the same in-memory key.
    let selfTestKeyStore: InMemoryKeyStore?

    private var statusItem: StatusItemController?
    private lazy var diagnosticsWindow = DiagnosticsWindowController()
    private lazy var historyWindow = HistoryWindowController(history: history, visuals: visuals, paster: paster) { [weak self] in
        self?.confirmClearHistory()
    }
    private lazy var settingsWindow = SettingsWindowController(app: self)
    private lazy var onboardingWindow = OnboardingWindowController(app: self)
    #if DEBUG
    private lazy var labWindow = LabWindowController(app: self)
    #endif
    private var expiryTask: Task<Void, Never>?
    private var maintenanceTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var storageOutcome: OpenOutcome = .created

    init() {
        AppSettings.registerDefaults()
        let time = OffsetTimeSource()
        let opened = Self.openStore(timeSource: time)
        let engine = HistoryEngine(store: opened.store, policy: AppSettings.capturePolicy, timeSource: time)
        let history = HistoryModel(engine: engine)
        let visuals = ClipVisuals(engine: engine)
        let capture = CaptureCoordinator(monitor: PasteboardMonitor(), engine: engine, history: history, timeSource: time)
        let input = InputCoordinator()
        let toast = ToastController()
        let paster = PasteController(history: history, capture: capture, input: input, toast: toast)

        timeSource = time
        storageDirectory = opened.store.directory
        storageProblem = opened.problem
        storageOutcome = opened.store.outcome
        selfTestKeyStore = opened.selfTestKeyStore
        self.engine = engine
        self.history = history
        self.visuals = visuals
        self.capture = capture
        self.input = input
        self.toast = toast
        self.paster = paster
        popup = PopupController(history: history, visuals: visuals, paster: paster)
    }

    func start() {
        NSApp.mainMenu = MainMenu.make()

        input.onHold = { [weak self] in self?.showPopup() }
        input.onPermissionChange = { [weak self] _ in self?.statusItem?.update() }
        input.start()
        popup.onClose = { [weak self] in self?.input.popupDidClose() }
        popup.onVisible = { [weak self] in self?.input.popupDidAppear() }
        hotKey.onPress = { [weak self] in self?.showPopup() }
        applyHotKey()

        capture.onStored = { [weak self] _ in self?.didStoreCopy() }
        capture.start()

        statusItem = StatusItemController(app: self)
        observeSystem()
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runMaintenance()
            }
        }
        runMaintenance()

        if case let .recoveredFromKeyLoss(movedTo) = storageOutcome, !Self.isSelfTest {
            showKeyLossNotice(movedTo: movedTo)
        }
        if !AppSettings.hasCompletedOnboarding, !Self.isSelfTest {
            showOnboarding()
        }
    }

    // MARK: Popup

    func showPopup() {
        guard !popup.isVisible else { return }
        popup.show(targetProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    var needsAttention: Bool {
        input.permission == .denied || capture.blockedReason == .accessDenied || storageProblem != nil
    }

    // MARK: Capture

    private func didStoreCopy() {
        if AppSettings.showCopyFeedback {
            toast.show(String(localized: "Kopiert"), systemImage: "checkmark")
        }
        scheduleExpiry()
    }

    func pauseCapture(for duration: TimeInterval?) {
        AppSettings.pausedUntil = duration.map { timeSource.now().addingTimeInterval($0) } ?? .distantFuture
        statusItem?.update()
    }

    func resumeCapture() {
        AppSettings.pausedUntil = nil
        statusItem?.update()
    }

    func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Verlauf löschen?")
        alert.informativeText = String(localized: "Alle Einträge außer den Favoriten werden endgültig gelöscht.")
        alert.addButton(withTitle: String(localized: "Löschen"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await history.perform { try await $0.deleteAll() }
            await history.perform { engine in _ = try await engine.runMaintenance() }
        }
    }

    // MARK: Maintenance

    /// Retention, orphan cleanup and the next expiry of a sensitive entry.
    func runMaintenance() {
        Task {
            await history.perform { engine in _ = try await engine.runMaintenance() }
            scheduleExpiry()
            statusItem?.update()
        }
    }

    /// Sleeps until the next sensitive entry expires, then removes it.
    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            guard let self, let next = try? await self.engine.nextExpiry() else { return }
            let delay = max(next.timeIntervalSince(self.timeSource.now()), 0) + 0.25
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let removed = (try? await self.engine.removeExpired()) ?? []
            if AppSettings.clearPasteboardAfterSensitive {
                self.paster.clearPasteboard(ifStillHolding: removed)
            }
            await self.history.reload()
            self.scheduleExpiry()
        }
    }

    #if DEBUG
    func advanceTime(days: Int) {
        timeSource.advance(by: TimeInterval(days) * 86_400)
        runMaintenance()
    }

    func resetTimeOffset() {
        timeSource.offset = 0
        runMaintenance()
    }
    #endif

    // MARK: Settings

    private func applySettings() {
        Task { await engine.setPolicy(AppSettings.capturePolicy) }
        input.applySettings()
        applyHotKey()
        statusItem?.update()
        runMaintenance()
    }

    private func applyHotKey() {
        guard AppSettings.hotKeyEnabled else {
            hotKey.register(nil)
            return
        }
        let shortcut = AppSettings.hotKey
        if hotKey.shortcut != shortcut {
            hotKey.register(shortcut)
        }
    }

    // MARK: Permissions

    func requestAccessibility() {
        if AccessibilityPermission.request() == .denied {
            AccessibilityPermission.openSystemSettings()
        }
    }

    func openPasteboardPrivacySettings() {
        // Privacy & Security → Paste from Other Apps (macOS 15.4+); falls back to the page.
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: Windows

    func showHistoryWindow() {
        historyWindow.show()
    }

    func showSettings() {
        settingsWindow.show()
    }

    func showDiagnostics() {
        diagnosticsWindow.show()
    }

    func showOnboarding() {
        onboardingWindow.show()
    }

    #if DEBUG
    func showLab() {
        labWindow.show()
    }
    #endif

    func reopen() {
        if AppSettings.hasCompletedOnboarding {
            showSettings()
        } else {
            showOnboarding()
        }
    }

    private func showKeyLossNotice(movedTo: URL) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Neuer Verlauf angelegt")
        alert.informativeText = String(localized: "Der bisherige Verlauf ließ sich nicht entschlüsseln (z. B. nach einem Wechsel der Signatur). Er wurde unverändert beiseitegelegt: \(movedTo.path)")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }

    // MARK: System events

    private func observeSystem() {
        observe(NotificationCenter.default, AppSettings.didChange) { app in
            app.applySettings()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        // ROADMAP M8: no reading while the screen is locked or the Mac sleeps.
        observe(workspace, NSWorkspace.willSleepNotification) { app in app.capture.stop() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { app in app.capture.stop() }
        observe(workspace, NSWorkspace.didWakeNotification) { app in app.resumeMonitoring() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { app in app.resumeMonitoring() }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { app in app.capture.stop() }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { app in app.resumeMonitoring() }
    }

    private func resumeMonitoring() {
        capture.start()
        runMaintenance()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor @Sendable (AppController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    // MARK: Storage

    private struct OpenedStore {
        var store: ClipStore
        var problem: String?
        var selfTestKeyStore: InMemoryKeyStore?
    }

    /// `~/Library/Application Support/<bundle-id>` with the key in the Keychain. If
    /// that fails, a temporary history for this session (and a hint in the menu).
    private static func openStore(timeSource: OffsetTimeSource) -> OpenedStore {
        let fileManager = FileManager.default
        let bundleID = Bundle.main.bundleIdentifier ?? "CopyPal"
        if isSelfTest {
            let base = fileManager.temporaryDirectory.appendingPathComponent("CopyPal-SelfTest-\(UUID().uuidString)")
            let keyStore = InMemoryKeyStore()
            // A failure here is a broken build; the self-test must stop loudly.
            let store = try! ClipStore.open(
                directory: base.appendingPathComponent("Data"),
                thumbnailDirectory: base.appendingPathComponent("Thumbnails"),
                keyStore: keyStore,
                timeSource: timeSource
            )
            return OpenedStore(store: store, selfTestKeyStore: keyStore)
        }

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        let thumbnails = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
        do {
            let store = try ClipStore.open(
                directory: support,
                thumbnailDirectory: thumbnails,
                keyStore: KeychainKeyStore(service: "\(bundleID).storage"),
                timeSource: timeSource
            )
            return OpenedStore(store: store)
        } catch {
            let fallback = fileManager.temporaryDirectory.appendingPathComponent("CopyPal-\(UUID().uuidString)")
            // Temporary folder with a fresh key: cannot fail unless the disk is unusable.
            let store = try! ClipStore.open(directory: fallback, keyStore: InMemoryKeyStore(), timeSource: timeSource)
            return OpenedStore(
                store: store,
                problem: String(localized: "Verlauf nur vorübergehend (Speicher nicht verfügbar)")
            )
        }
    }
}
