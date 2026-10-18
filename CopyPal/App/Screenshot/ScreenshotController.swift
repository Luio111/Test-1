import AppKit
import Observation
import CopyPalCore
import CopyPalServices
import CopyPalSystem

/// Drives the screenshot feature (ROADMAP M11): the hot key, the Screen Recording
/// permission gate and the overlay session – frozen frame, snapping, selection,
/// capture and the scrolling capture. Decisions come from `ScreenshotSelectionMachine`;
/// this class only carries out its effects. Observable for the settings page and the lab.
@MainActor
@Observable
final class ScreenshotController {
    /// A session is running (from the hot key until the overlay closes).
    private(set) var isActive = false
    /// The overlay panels are on screen.
    private(set) var isOverlayVisible = false
    /// The permission window is open.
    private(set) var isShowingPermissionHint = false
    private(set) var permissionState: PermissionState = ScreenCapturePermission.state
    /// The system prompt was shown once; from then on only System Settings can help.
    private(set) var permissionAsked = AppSettings.screenshotPermissionAsked
    /// False when another app owns the shortcut (Carbon refused the registration).
    private(set) var hotKeyAvailable = true

    /// Lab: draws every detected element and panel.
    var showsDetectedRegions = false
    /// Lab: scrolls without parking the pointer over the selection (routing experiments).
    var scrollsWithoutCursorWarp = false
    /// Lab: how long the frozen frame of all screens took.
    private(set) var lastFreezeMilliseconds: Double?
    /// Lab: what the last scroll step did.
    private(set) var lastStepDescription: String?

    @ObservationIgnored private unowned let app: AppController
    @ObservationIgnored private var permissionWindow: ScreenshotPermissionWindowController?
    /// A start that waits for the permission window to report the grant.
    @ObservationIgnored private var startPending = false
    /// The grant arrived; the capture starts when the permission window has closed.
    @ObservationIgnored private var startAfterPermissionWindow = false
    @ObservationIgnored private var appBeforePermissionWindow: NSRunningApplication?
    @ObservationIgnored private var didWarmUp = false
    /// Bumped whenever a session ends: late results of an old session are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var machine = ScreenshotSelectionMachine(screens: [])
    @ObservationIgnored private var screens: [ScreenState] = []
    @ObservationIgnored private var windows: [WindowInfo] = []
    @ObservationIgnored private var sourceApp: NSRunningApplication?
    @ObservationIgnored private var status: ScreenshotStatus = .none
    @ObservationIgnored private var pointer: CGPoint = .zero
    /// The selection the machine works on (it forgets it once it finishes).
    @ObservationIgnored private var selectedRect: CGRect?
    @ObservationIgnored private var session: ScrollSession?
    @ObservationIgnored private var liveFrame: ImageBox?
    @ObservationIgnored private var stepTask: Task<Void, Never>?
    /// The window the scrolling capture works in; another one under the selection stops it.
    @ObservationIgnored private var stepWindowNumber: Int?
    /// After ⌫ the screen is a step ahead of the stitched part: the next step takes the
    /// current view without scrolling first.
    @ObservationIgnored private var needsResync = false
    @ObservationIgnored private var warpedFrom: CGPoint?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// One screen of the session.
    private struct ScreenState {
        let frame: CGRect
        /// What can be captured: the frame, below the menu bar before macOS 14.2.
        let bounds: CGRect
        let display: ScreenCaptureEngine.Display
        let panel: ScreenshotOverlayPanel
        let frozen: ImageBox
        var regionMap: RegionMap?
    }

    init(app: AppController) {
        self.app = app
    }

    /// Every overlay panel is on the Space the user sees (self-test, full screen).
    var isOverlayOnActiveSpace: Bool {
        !screens.isEmpty && screens.allSatisfy { $0.panel.isOnActiveSpace }
    }

    /// Screen Recording worked once and is gone now: a warning in the menu bar.
    var permissionRevoked: Bool {
        AppSettings.screenshotEnabled && AppSettings.screenCaptureWasGranted && permissionState == .denied
    }

    // MARK: Hot key and menu

    /// ⌘⇧A: starts a session, or cancels the running one.
    func toggle() {
        if isActive {
            cancel()
        } else {
            start()
        }
    }

    /// Starts a session when the permission is there, else shows the permission window.
    func start() {
        guard AppSettings.screenshotEnabled, !isActive else { return }
        if app.popup.isVisible {
            app.popup.close(retracting: false)
        }
        refreshPermission()
        guard permissionState == .granted else {
            // The window activates CopyPal; the app in front now gets the focus back
            // before a capture that starts after the grant.
            appBeforePermissionWindow = NSWorkspace.shared.frontmostApplication
            startPending = true
            showPermissionWindow()
            return
        }
        beginSession()
    }

    /// Ends the session without a capture (Esc, the hot key again, sleep, a screen change).
    func cancel() {
        guard isActive else { return }
        endSession()
    }

    func setHotKeyAvailable(_ available: Bool) {
        if hotKeyAvailable != available {
            hotKeyAvailable = available
        }
    }

    // MARK: Permission

    func refreshPermission() {
        let state = ScreenCapturePermission.state
        if state != permissionState {
            permissionState = state
            app.attentionDidChange()
        }
    }

    /// The system prompt (once per app identity), only ever from a button.
    func requestPermission() {
        AppSettings.screenshotPermissionAsked = true
        permissionAsked = true
        ScreenCapturePermission.request()
        refreshPermission()
    }

    func openSystemSettings() {
        ScreenCapturePermission.openSystemSettings()
    }

    func showPermissionWindow() {
        let window = permissionWindow ?? ScreenshotPermissionWindowController(controller: self)
        permissionWindow = window
        isShowingPermissionHint = true
        window.show()
    }

    func closePermissionWindow() {
        permissionWindow?.close()
    }

    /// Relaunches CopyPal: macOS applies a Screen Recording grant to new processes only.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    /// „Kürzel ändern …“ in the permission window.
    func openShortcutSettings() {
        app.showSettings()
    }

    /// Called by the permission window once ScreenCaptureKit confirmed the grant: the
    /// waiting capture starts after the window is gone, so it neither shows up in the
    /// frozen frame nor counts as the app being captured.
    func permissionWindowDidVerify() {
        refreshPermission()
        if startPending {
            startAfterPermissionWindow = true
        }
        startPending = false
    }

    /// Called by the permission window.
    func permissionWindowDidClose() {
        isShowingPermissionHint = false
        startPending = false
        refreshPermission()
        let previous = appBeforePermissionWindow
        appBeforePermissionWindow = nil
        guard startAfterPermissionWindow else { return }
        startAfterPermissionWindow = false
        guard permissionState == .granted, AppSettings.screenshotEnabled, !isActive else { return }
        if let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            _ = previous.activate()
        }
        Task { [weak self] in
            // Time for the window to fade and the other app to come to the front.
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !self.isActive, AppSettings.screenshotEnabled else { return }
            self.beginSession()
        }
    }

    // MARK: Session

    private func beginSession() {
        startPending = false
        guard !isActive else { return }
        isActive = true
        generation += 1
        let current = generation
        sourceApp = NSWorkspace.shared.frontmostApplication
        Task {
            await self.openOverlay(generation: current)
        }
    }

    /// Freezes every screen before any overlay appears – system dialogs about the
    /// capture can never hide under it – then shows one overlay per screen.
    private func openOverlay(generation current: Int) async {
        let started = ContinuousClock.now
        let targets: [(screen: NSScreen, display: ScreenCaptureEngine.Display)] = NSScreen.screens.compactMap { screen in
            ScreenCaptureEngine.display(for: screen).map { (screen: screen, display: $0) }
        }
        guard !targets.isEmpty else {
            sessionFailed(.displayNotFound)
            return
        }
        // The capture can wait for a macOS dialog about Screen Recording, perhaps on
        // another Space: say so instead of showing nothing.
        let waitingHint = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled, let self, current == self.generation, self.isActive, !self.isOverlayVisible else { return }
            self.app.toast.show(String(localized: "Wartet auf macOS …"), systemImage: "hourglass", duration: .seconds(3))
        }
        defer { waitingHint.cancel() }
        if !didWarmUp {
            await ScreenCaptureEngine.warmUp()
            didWarmUp = true
        }
        var frozen: [ImageBox] = []
        do {
            for target in targets {
                frozen.append(try await ScreenCaptureEngine.captureDisplay(target.display))
            }
        } catch let failure as ScreenCaptureEngine.Failure {
            if current == generation { sessionFailed(failure) }
            return
        } catch {
            if current == generation { sessionFailed(.underlying(String(describing: error))) }
            return
        }
        guard current == generation, isActive else { return }
        lastFreezeMilliseconds = Self.milliseconds(since: started)
        if let waited = lastFreezeMilliseconds, waited >= 1_500 {
            // „Wartet auf macOS …“ must not end up in the picture.
            app.toast.hide()
        }
        if !AppSettings.screenCaptureWasGranted {
            AppSettings.screenCaptureWasGranted = true
        }
        if permissionState != .granted {
            permissionState = .granted
            app.attentionDidChange()
        }

        windows = WindowGeometry.snapTargets(WindowList.onScreen(), excludingPID: ProcessInfo.processInfo.processIdentifier)
        screens = zip(targets, frozen).map { pair in
            let (target, image) = pair
            let view = ScreenshotOverlayView(frame: CGRect(origin: .zero, size: target.screen.frame.size))
            let panel = ScreenshotOverlayPanel(screenFrame: target.screen.frame, view: view)
            view.onInput = { [weak self] input in
                self?.handle(input)
            }
            view.onEntered = { [weak panel] in
                panel?.makeKey()
            }
            return ScreenState(
                frame: target.screen.frame,
                bounds: Self.capturableBounds(of: target.screen),
                display: target.display,
                panel: panel,
                frozen: image,
                regionMap: nil
            )
        }
        machine = ScreenshotSelectionMachine(screens: screens.map(\.bounds))
        status = .none
        pointer = NSEvent.mouseLocation

        installMonitors()
        for state in screens {
            state.panel.overlayView.apply(scene(for: state))
            // New panels each session: over another app's full-screen Space the first
            // order-in can land on the desktop behind it (seen with the popup).
            if !state.panel.orderFrontOnActiveSpace() {
                Log.app.error("Bildschirmfoto: Overlay liegt nicht auf dem aktiven Space")
            }
        }
        (screens.first { $0.frame.contains(pointer) } ?? screens.first)?.panel.makeKey()
        isOverlayVisible = true
        apply(machine.start())
        handle(.mouseMoved(pointer))
        analyzeRegions(generation: current)
        if let hint = hintText() {
            speak(hint)
        }
        Log.app.info("Bildschirmfoto: Overlay auf \(self.screens.count, privacy: .public) Bildschirm(en), eingefroren in \(self.lastFreezeMilliseconds ?? 0, privacy: .public) ms")
    }

    /// Contrast regions per screen, off the main thread; until they arrive only the
    /// window and the screen are offered.
    private func analyzeRegions(generation current: Int) {
        for (index, state) in screens.enumerated() {
            let image = state.frozen
            let cellPixels = max(Int((2 * state.display.scale).rounded()), 1)
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let plane = ImageConversion.lumaPlane(image.image, cellPixels: cellPixels) else { return }
                let map = RegionDetector.analyze(plane)
                await self?.regionMapReady(map, screenIndex: index, generation: current)
            }
        }
    }

    private func regionMapReady(_ map: RegionMap, screenIndex: Int, generation current: Int) {
        guard current == generation, screens.indices.contains(screenIndex) else { return }
        screens[screenIndex].regionMap = map
        if case let .hovering(hover) = machine.state {
            apply([.requestCandidates(hover.pointer, windowsOnly: hover.windowsOnly)])
        }
        if showsDetectedRegions {
            redraw()
        }
    }

    private func sessionFailed(_ failure: ScreenCaptureEngine.Failure) {
        endSession()
        switch failure {
        case .permissionDenied:
            // The preflight said yes, ScreenCaptureKit says no: revoked, or a relaunch
            // is needed. The permission window tells which.
            if permissionState != .denied {
                permissionState = .denied
                app.attentionDidChange()
            }
            appBeforePermissionWindow = sourceApp
            startPending = true
            showPermissionWindow()
        default:
            Log.app.error("Bildschirmfoto fehlgeschlagen: \(String(describing: failure), privacy: .public)")
            app.toast.show(String(localized: "Bildschirmfoto fehlgeschlagen"), systemImage: "exclamationmark.triangle")
        }
    }

    private func endSession() {
        generation += 1
        stepTask?.cancel()
        stepTask = nil
        if let warpedFrom {
            ScrollSynthesizer.restoreCursor(warpedFrom)
            self.warpedFrom = nil
        }
        removeMonitors()
        for state in screens {
            state.panel.orderOut(nil)
        }
        screens = []
        windows = []
        resetScroll()
        selectedRect = nil
        status = .none
        machine = ScreenshotSelectionMachine(screens: [])
        isOverlayVisible = false
        isActive = false
    }

    // MARK: Input

    private func handle(_ input: ScreenshotInput) {
        guard isOverlayVisible else { return }
        switch input {
        case let .mouseMoved(point), let .mouseDown(point, _), let .mouseDragged(point, _), let .mouseUp(point, _):
            pointer = point
        default:
            break
        }
        apply(machine.handle(input))
        if case .mouseMoved = input, case .hovering = machine.state, isOverlayVisible {
            redraw()
        }
    }

    /// Carries out what the machine decided.
    private func apply(_ effects: [ScreenshotEffect]) {
        var needsRedraw = false
        for effect in effects {
            guard isActive else { return }
            switch effect {
            case let .requestCandidates(point, windowsOnly):
                apply(machine.handle(.candidatesChanged(candidates(at: point, windowsOnly: windowsOnly))))
            case .redraw:
                needsRedraw = true
            case let .capture(rect):
                captureSingle(rect)
            case .finishStitched:
                finishStitched()
            case let .beginStep(direction):
                beginStep(direction)
            case .cancelStep:
                // The running step completes; the machine starts no further one.
                break
            case .undoSlice:
                undoSlice()
            case let .status(newStatus):
                if newStatus != status {
                    announceStatus(newStatus)
                }
                status = newStatus
                needsRedraw = true
            case let .announce(announcement):
                announce(announcement)
            case .dismiss:
                endSession()
                return
            case .beep:
                NSSound.beep()
            }
        }
        if needsRedraw, isOverlayVisible {
            syncSelection()
            redraw()
        }
    }

    /// Keeps the scrolling capture in step with the selection: a new or discarded
    /// selection starts over.
    private func syncSelection() {
        switch machine.state {
        case let .selected(selection):
            selectedRect = selection.rect
            if selection.stitched == nil, stepTask == nil {
                resetScroll()
            }
        case let .extending(extensionState):
            selectedRect = extensionState.selection.rect
        case .hovering, .pressed, .dragging:
            selectedRect = nil
            resetScroll()
        case .idle, .finished:
            break
        }
    }

    private func resetScroll() {
        session = nil
        liveFrame = nil
        stepWindowNumber = nil
        needsResync = false
    }

    /// The rungs under `point`: element, text block and flat region from the contrast
    /// analysis (cut to the window), the window, the screen.
    private func candidates(at point: CGPoint, windowsOnly: Bool) -> [SnapCandidate] {
        guard let state = screens.first(where: { $0.frame.contains(point) }) else { return [] }
        let window = WindowGeometry.window(at: point, in: windows)
        var element: CGRect?
        var block: CGRect?
        var panel: CGRect?
        if !windowsOnly, let map = state.regionMap {
            let scale = state.display.scale
            let cell = CGFloat(map.cell)
            let local = ScreenshotGeometry.displayLocal(CGRect(origin: point, size: .zero), in: state.frame)
            let cellX = Int((local.minX * scale / cell).rounded(.down))
            let cellY = Int((local.minY * scale / cell).rounded(.down))
            let windowCells = window.map { info in
                Self.cells(ScreenshotGeometry.pixels(ScreenshotGeometry.displayLocal(info.frame, in: state.frame), scale: scale), cell: map.cell)
            }
            let rungs = map.rungs(atCell: cellX, cellY, within: windowCells)
            func appKit(_ cells: PixelRect?) -> CGRect? {
                guard let cells else { return nil }
                let pixels = PixelRect(x: cells.x * map.cell, y: cells.y * map.cell, width: cells.width * map.cell, height: cells.height * map.cell)
                return ScreenshotGeometry.appKit(fromDisplayLocal: ScreenshotGeometry.points(pixels, scale: scale), in: state.frame)
            }
            element = appKit(rungs.element)
            block = appKit(rungs.block)
            panel = appKit(rungs.panel)
        }
        return SnapCandidateChain.make(element: element, block: block, panel: panel, window: window, screen: state.bounds, windowsOnly: windowsOnly)
    }

    // MARK: Keys and system events

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let type = event.type
            let keyCode = event.keyCode
            let modifiers = KeyModifiers(event.modifierFlags)
            let isRepeat = type == .keyDown && event.isARepeat
            let consumed = MainActor.assumeIsolated {
                self?.handleKey(type: type, keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat) ?? false
            }
            return consumed ? nil : event
        }
        // Another app taking the keyboard ends the session (switching between our own
        // overlay panels does not).
        observe(NotificationCenter.default, NSWindow.didResignKeyNotification) { controller in
            controller.checkKeyStatus()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { controller in
            controller.handle(.externalCancel)
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    private func handleKey(type: NSEvent.EventType, keyCode: UInt16, modifiers: KeyModifiers, isRepeat: Bool) -> Bool {
        guard isOverlayVisible else { return false }
        switch type {
        case .flagsChanged:
            handle(.flagsChanged(modifiers))
            return false
        case .keyDown:
            if let key = ScreenshotKeyMap.key(forKeyCode: keyCode) {
                handle(.keyDown(key, modifiers, isRepeat: isRepeat))
            }
            return true
        case .keyUp:
            if let key = ScreenshotKeyMap.key(forKeyCode: keyCode) {
                handle(.keyUp(key))
            }
            return true
        default:
            return false
        }
    }

    private func checkKeyStatus() {
        Task { [weak self] in
            // When the pointer moves to another screen, one of our panels resigns and
            // the next becomes key a moment later.
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, self.isOverlayVisible else { return }
            if !self.screens.contains(where: { $0.panel.isKeyWindow }) {
                self.handle(.lostKeyStatus)
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor @Sendable (ScreenshotController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    // MARK: Capture

    /// A fresh single frame of `rect`, without the overlay, then publish.
    private func captureSingle(_ rect: CGRect) {
        guard let state = screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) else {
            endSession()
            return
        }
        let current = generation
        let display = state.display
        let pixels = ScreenshotGeometry.pixels(ScreenshotGeometry.displayLocal(rect, in: state.frame), scale: display.scale)
        let excluded = overlayWindowIDs
        let source = sourceBundleID(for: rect)
        let caption = capturedFrom(for: rect)
        Task {
            let result: Result<ImageBox, ScreenCaptureEngine.Failure>
            do {
                result = .success(try await ScreenCaptureEngine.capture(pixels, of: display, excludingWindowIDs: excluded))
            } catch let failure as ScreenCaptureEngine.Failure {
                result = .failure(failure)
            } catch {
                result = .failure(.underlying(String(describing: error)))
            }
            guard current == self.generation else { return }
            switch result {
            case let .success(image):
                self.endSession()
                await self.publish(image, scale: display.scale, sourceBundleID: source, capturedFrom: caption)
            case let .failure(failure):
                self.sessionFailed(failure)
            }
        }
    }

    /// The stitched result of the scrolling capture.
    private func finishStitched() {
        guard let session, let rect = selectedRect,
              let state = screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) else {
            if let rect = selectedRect {
                captureSingle(rect)
            } else {
                endSession()
            }
            return
        }
        let current = generation
        let scale = state.display.scale
        let source = sourceBundleID(for: rect)
        let caption = capturedFrom(for: rect)
        let snapshot = session
        Task {
            let image = await Task.detached(priority: .userInitiated) { () -> ImageBox? in
                ImageConversion.cgImage(snapshot.composite()).map { ImageBox($0) }
            }.value
            guard current == self.generation else { return }
            self.endSession()
            if let image {
                await self.publish(image, scale: scale, sourceBundleID: source, capturedFrom: caption)
            } else {
                self.app.toast.show(String(localized: "Bildschirmfoto fehlgeschlagen"), systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func publish(_ image: ImageBox, scale: CGFloat, sourceBundleID: String?, capturedFrom: String) async {
        let outcome = await ScreenshotResultWriter.publish(image, scale: scale, sourceBundleID: sourceBundleID, capturedFrom: capturedFrom, app: app)
        let symbol = "camera.viewfinder"
        switch outcome {
        case let .stored(_, downscaled: downscaled):
            // The halved image is also what lies on the pasteboard: say so.
            app.toast.show(
                downscaled ? String(localized: "Bildschirmfoto kopiert – auf halbe Auflösung verkleinert") : String(localized: "Bildschirmfoto kopiert"),
                systemImage: symbol
            )
        case .pasteboardOnly(.paused):
            app.toast.show(String(localized: "Bildschirmfoto in der Zwischenablage (Aufzeichnung pausiert)"), systemImage: symbol)
        case .pasteboardOnly(.ignoredApp):
            app.toast.show(String(localized: "Bildschirmfoto nur auf diesem Mac (App wird ignoriert)"), systemImage: symbol)
        case .pasteboardOnly(.tooLarge):
            app.toast.show(String(localized: "Bildschirmfoto verkleinert kopiert – zu groß für den Verlauf"), systemImage: symbol)
        case let .failed(message):
            Log.app.error("Bildschirmfoto nicht gespeichert: \(message, privacy: .public)")
            app.toast.show(String(localized: "Bildschirmfoto fehlgeschlagen"), systemImage: "exclamationmark.triangle")
        }
    }

    /// The app whose window the selection covers, for the ignore list. An ignored app
    /// visible anywhere in the selection (centre or a corner) wins, so a password
    /// manager next to a browser window still keeps the result off the history and
    /// off other devices.
    private func sourceBundleID(for rect: CGRect) -> String? {
        let inner = rect.insetBy(dx: min(2, rect.width / 4), dy: min(2, rect.height / 4))
        let points = [
            CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY),
            CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY),
        ]
        let bundleIDs = points.compactMap { point in
            WindowGeometry.window(at: point, in: windows).flatMap { NSRunningApplication(processIdentifier: $0.ownerPID)?.bundleIdentifier }
        }
        let ignored = AppSettings.ignoredBundleIDs
        if let hit = bundleIDs.first(where: { ignored.contains($0) }) {
            return hit
        }
        if let bundleID = bundleIDs.first {
            return bundleID
        }
        return sourceApp?.bundleIdentifier
    }

    /// "Safari – JIRA-1234": the app and the title of the window under the selection's
    /// centre, so the screenshot can be told apart and found in the history.
    private func capturedFrom(for rect: CGRect) -> String {
        guard let window = WindowGeometry.window(at: CGPoint(x: rect.midX, y: rect.midY), in: windows) else {
            return WindowGeometry.caption(appName: sourceApp?.localizedName, windowTitle: nil)
        }
        let appName = NSRunningApplication(processIdentifier: window.ownerPID)?.localizedName
        return WindowGeometry.caption(appName: appName, windowTitle: window.title)
    }

    private var overlayWindowIDs: Set<CGWindowID> {
        Set(screens.map { CGWindowID(clamping: $0.panel.windowNumber) })
    }

    // MARK: Scrolling capture

    private func beginStep(_ direction: ScrollDirection) {
        guard case let .extending(extensionState) = machine.state else { return }
        let rect = extensionState.selection.rect
        selectedRect = rect
        // Synthetic scroll events need the Accessibility permission (as ⌘V does).
        guard AccessibilityPermission.state == .granted else {
            apply(machine.handle(.stepFinished(.stalled(final: true))))
            status = .needsAccessibility
            redraw()
            return
        }
        guard let index = screens.firstIndex(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) else {
            apply(machine.handle(.stepFinished(.stalled(final: true))))
            return
        }
        var selectionWindowID: Int?
        if case let .candidate(candidate) = extensionState.selection.origin, case let .window(id) = candidate.kind {
            selectionWindowID = Int(id)
        }
        let current = generation
        stepTask = Task {
            await self.runStep(direction, rect: rect, screenIndex: index, generation: current, selectionWindowID: selectionWindowID)
        }
    }

    /// One step (ROADMAP M11): scroll the content under the selection, wait until it
    /// stands still, join the new frame to the capture.
    private func runStep(_ direction: ScrollDirection, rect: CGRect, screenIndex: Int, generation current: Int, selectionWindowID: Int?) async {
        let started = ContinuousClock.now
        // The session may have ended between scheduling and running this step.
        guard current == generation, screens.indices.contains(screenIndex) else { return }
        let state = screens[screenIndex]
        let display = state.display
        let pixels = ScreenshotGeometry.pixels(ScreenshotGeometry.displayLocal(rect, in: state.frame), scale: display.scale)
        let excluded = overlayWindowIDs
        let scale = max(Int(display.scale.rounded()), 1)

        // The first frame: what the selection shows before any scrolling.
        if session == nil {
            let first = await Self.frame(pixels, of: display, excluding: excluded)
            guard current == generation else { return }
            guard let first else {
                finishStep(.stalled(final: true), generation: current)
                return
            }
            session = ScrollSession(firstFrame: first, scale: scale)
        }

        // Scroll events go to the window under the pointer: it must still be the one
        // the selection was made on (a dialog in front stops the capture).
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let owner = WindowList.windowNumber(at: center, belowWindowNumber: state.panel.windowNumber)
        if let expected = selectionWindowID ?? stepWindowNumber, owner != expected {
            finishStep(.noMovement(first: true), generation: current)
            return
        }
        stepWindowNumber = owner

        let reversed = AppSettings.screenshotScrollReversed
        var next: PixelBuffer?
        if needsResync {
            // After ⌫ the view is already past the stitched part: take it as it is.
            needsResync = false
            next = await Self.settledFrame(pixels, of: display, excluding: excluded)
        } else {
            for overlay in screens {
                overlay.panel.ignoresMouseEvents = true
            }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let location = ScreenshotGeometry.flipped(center, primaryHeight: primaryHeight)
            if !scrollsWithoutCursorWarp {
                warpedFrom = ScrollSynthesizer.warpCursor(to: location)
            }
            let delta = ScrollPlanner.stepPoints(selectionHeight: rect.height)
            await ScrollSynthesizer.post(chunks: ScrollPlanner.chunks(deltaPoints: delta, direction: direction, reversed: reversed), at: location)
            next = await Self.settledFrame(pixels, of: display, excluding: excluded)
            // Some apps ignore pixel deltas: one line-based retry on the first step.
            if let session, session.steps == 0, let frame = next, frame == session.stitcher.latestFrame {
                let lines: Int32 = (direction == .down) != reversed ? -3 : 3
                ScrollSynthesizer.postLines(lines, at: location)
                next = await Self.settledFrame(pixels, of: display, excluding: excluded)
            }
            if let warpedFrom {
                ScrollSynthesizer.restoreCursor(warpedFrom)
                self.warpedFrom = nil
            }
            for overlay in screens {
                overlay.panel.ignoresMouseEvents = false
            }
        }

        guard current == generation else { return }
        guard let frame = next, let base = session else {
            finishStep(.stalled(final: true), generation: current)
            return
        }
        let (updated, outcome) = await Task.detached(priority: .userInitiated) { () -> (ScrollSession, StepOutcome) in
            var working = base
            let outcome = working.accept(frame, direction: direction)
            return (working, outcome)
        }.value
        let live = await Task.detached(priority: .userInitiated) { () -> ImageBox? in
            ImageConversion.cgImage(frame).map { ImageBox($0) }
        }.value
        guard current == generation else { return }
        session = updated
        liveFrame = live
        lastStepDescription = String(
            format: "%@ · %.0f ms · %ld Abschnitte · %ld px",
            String(describing: outcome), Self.milliseconds(since: started), updated.info.sections, updated.info.heightPixels
        )
        finishStep(outcome, generation: current)
    }

    private func finishStep(_ outcome: StepOutcome, generation current: Int) {
        guard current == generation else { return }
        stepTask = nil
        apply(machine.handle(.stepFinished(outcome)))
    }

    /// ⌫: drops the newest section without scrolling back.
    private func undoSlice() {
        guard var working = session else {
            apply(machine.handle(.sliceRemoved(nil)))
            return
        }
        let undone = working.undo()
        session = working
        if undone {
            needsResync = true
        }
        liveFrame = ImageConversion.cgImage(working.stitcher.latestFrame).map { ImageBox($0) }
        let info: StitchInfo? = working.stitcher.sectionCount > 0 ? working.info : nil
        apply(machine.handle(.sliceRemoved(info)))
    }

    /// Captures `pixels` (without the overlay) as a pixel buffer.
    private static func frame(_ pixels: PixelRect, of display: ScreenCaptureEngine.Display, excluding excluded: Set<CGWindowID>) async -> PixelBuffer? {
        guard let image = try? await ScreenCaptureEngine.capture(pixels, of: display, excludingWindowIDs: excluded) else {
            return nil
        }
        return await Task.detached(priority: .userInitiated) {
            ImageConversion.pixelBuffer(image.image)
        }.value
    }

    /// Waits until two frames in a row agree (scrolling and its animation are over),
    /// at most 0.7 s.
    private static func settledFrame(_ pixels: PixelRect, of display: ScreenCaptureEngine.Display, excluding excluded: Set<CGWindowID>) async -> PixelBuffer? {
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, var previous = await frame(pixels, of: display, excluding: excluded) else { return nil }
        let deadline = ContinuousClock.now + .milliseconds(700)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(60))
            if Task.isCancelled { return nil }
            guard let next = await frame(pixels, of: display, excluding: excluded) else { return previous }
            if next == previous { return next }
            previous = next
        }
        return previous
    }

    // MARK: Drawing

    private func redraw() {
        for state in screens {
            state.panel.overlayView.apply(scene(for: state))
        }
    }

    private func scene(for state: ScreenState) -> OverlayScene {
        var scene = OverlayScene()
        scene.frozen = state.frozen
        let origin = state.frame.origin
        func local(_ rect: CGRect?) -> CGRect? {
            guard let rect, rect.intersects(state.frame) else { return nil }
            return rect.offsetBy(dx: -origin.x, dy: -origin.y)
        }
        var selection: CGRect?
        switch machine.state {
        case let .hovering(hover):
            scene.candidate = local(hover.candidate?.rect)
            if hover.candidate == nil, state.frame.contains(hover.pointer) {
                scene.pointer = CGPoint(x: hover.pointer.x - origin.x, y: hover.pointer.y - origin.y)
                let topLeft = ScreenshotGeometry.displayLocal(CGRect(origin: hover.pointer, size: .zero), in: state.frame)
                scene.coordinatesText = "\(Int(topLeft.minX)), \(Int(topLeft.minY))"
            }
        case let .pressed(press):
            scene.candidate = local(press.candidate?.rect)
        case let .dragging(drag):
            selection = drag.rect
        case let .selected(selected):
            selection = selected.rect
            scene.handlesVisible = true
        case let .extending(extensionState):
            selection = extensionState.selection.rect
        case .idle, .finished:
            break
        }
        if let selection, let rect = local(selection) {
            scene.selection = rect
            scene.sizeText = "\(Int(selection.width.rounded()).formatted()) × \(Int(selection.height.rounded()).formatted())"
            scene.live = liveFrame
        }
        // Hint and status on the screen the user works on.
        let focus = selection.map { CGPoint(x: $0.midX, y: $0.midY) } ?? pointer
        let isActiveScreen = state.frame.contains(focus) || (screens.first?.frame == state.frame && !screens.contains { $0.frame.contains(focus) })
        if isActiveScreen {
            scene.hintText = hintText()
            scene.statusText = statusText()
        }
        if showsDetectedRegions, let map = state.regionMap {
            scene.debugBoxes = Self.debugBoxes(map, in: state).map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        }
        return scene
    }

    private func hintText() -> String? {
        switch machine.hint {
        case .hovering:
            return String(localized: "Klick nimmt auf · Ziehen wählt frei · ⇥ größer · Leertaste nur Fenster · ↓ erweitern · Esc")
        case .windowsOnly:
            return String(localized: "Nur Fenster · Leertaste zurück")
        case .dragging:
            return String(localized: "⇧ Quadrat · ⌥ von der Mitte · Leertaste verschieben")
        case .selected:
            return String(localized: "⏎ aufnehmen · ↓ ↑ erweitern · ⌘-Pfeile verschieben · Esc")
        case .selectedStitched:
            return String(localized: "⏎ aufnehmen · ↓ ↑ weiter · ⌫ Abschnitt zurück · Esc")
        case .extending:
            return String(localized: "↓ halten für mehr · ⌥↓ bis zum Ende · Esc stoppt")
        case nil:
            return nil
        }
    }

    private func statusText() -> String? {
        statusText(for: status)
    }

    private func statusText(for status: ScreenshotStatus) -> String? {
        switch status {
        case .none:
            return nil
        case .extending:
            return String(localized: "Erweitert …")
        case let .sections(info):
            let sectionCount = info.sections
            let pixels = info.heightPixels.formatted()
            return String(localized: "\(sectionCount) Abschnitte · \(pixels) px")
        case .endReached:
            return String(localized: "Ende erreicht")
        case .noScroll:
            return String(localized: "Inhalt scrollt nicht")
        case .noOverlapRetry:
            return String(localized: "Kein Übergang gefunden – ↓ versucht es erneut")
        case .noOverlapStop:
            return String(localized: "Kein Übergang gefunden – bisheriger Teil bleibt")
        case .capReached:
            return String(localized: "Maximale Höhe erreicht")
        case .needsAccessibility:
            return String(localized: "Scroll-Aufnahme braucht Bedienungshilfen")
        case let .escArmed(sections):
            let sectionCount = sections
            return String(localized: "Esc erneut verwirft \(sectionCount) Abschnitte")
        }
    }

    private func announce(_ announcement: ScreenshotAnnouncement) {
        let message: String
        switch announcement {
        case let .selection(width, height):
            let size = (width: width, height: height)
            message = String(localized: "Auswahl \(size.width) × \(size.height)")
        case let .sections(count):
            let sectionCount = count
            message = String(localized: "Abschnitt \(sectionCount)")
        }
        speak(message)
    }

    /// Status lines VoiceOver should hear; the running count is announced per section.
    private func announceStatus(_ newStatus: ScreenshotStatus) {
        switch newStatus {
        case .none, .extending, .sections:
            return
        case .escArmed:
            if let text = statusText(for: newStatus) { speak(text, high: true) }
        default:
            if let text = statusText(for: newStatus) { speak(text) }
        }
    }

    private func speak(_ message: String, high: Bool = false) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: (high ? NSAccessibilityPriorityLevel.high : .medium).rawValue,
            ]
        )
    }

    // MARK: Helpers

    /// Before macOS 14.2 ScreenCaptureKit leaves the menu bar out of display captures.
    private static func capturableBounds(of screen: NSScreen) -> CGRect {
        if #available(macOS 14.2, *) {
            return screen.frame
        }
        var bounds = screen.frame
        bounds.size.height = screen.visibleFrame.maxY - screen.frame.minY
        return bounds
    }

    /// Device pixels → region cells, rounded outward.
    private static func cells(_ pixels: PixelRect, cell: Int) -> PixelRect {
        let x0 = pixels.x / cell
        let y0 = pixels.y / cell
        let x1 = (pixels.maxX + cell - 1) / cell
        let y1 = (pixels.maxY + cell - 1) / cell
        return PixelRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
    }

    /// Lab: all element and panel boxes of a screen in AppKit coordinates.
    private static func debugBoxes(_ map: RegionMap, in state: ScreenState) -> [CGRect] {
        (map.elementBoxes + map.panelBoxes).map { cells in
            let pixels = PixelRect(x: cells.x * map.cell, y: cells.y * map.cell, width: cells.width * map.cell, height: cells.height * map.cell)
            return ScreenshotGeometry.appKit(fromDisplayLocal: ScreenshotGeometry.points(pixels, scale: state.display.scale), in: state.frame)
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let (seconds, attoseconds) = (ContinuousClock.now - start).components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }

    // MARK: Self-test

    #if DEBUG
    enum SelfTestCapture {
        case stored(ClipItem)
        case pasteboardOnly(String)
        case permissionDenied
        case failed(String)
    }

    /// A capture of `rect` straight into the pasteboard and the history, without the
    /// overlay (CI cannot click and drag).
    func captureForSelfTest(rect: CGRect) async -> SelfTestCapture {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }),
              let display = ScreenCaptureEngine.display(for: screen) else {
            return .failed("kein Bildschirm")
        }
        let clipped = rect.intersection(screen.frame)
        let pixels = ScreenshotGeometry.pixels(ScreenshotGeometry.displayLocal(clipped, in: screen.frame), scale: display.scale)
        do {
            let image = try await ScreenCaptureEngine.capture(pixels, of: display)
            switch await ScreenshotResultWriter.publish(image, scale: display.scale, sourceBundleID: nil, capturedFrom: "CopyPal Selbsttest", app: app) {
            case let .stored(item, downscaled: _):
                return .stored(item)
            case let .pasteboardOnly(reason):
                return .pasteboardOnly(String(describing: reason))
            case let .failed(message):
                return .failed(message)
            }
        } catch ScreenCaptureEngine.Failure.permissionDenied {
            return .permissionDenied
        } catch {
            return .failed(String(describing: error))
        }
    }
    #endif
}
