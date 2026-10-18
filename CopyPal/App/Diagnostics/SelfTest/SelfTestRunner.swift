#if DEBUG
import AppKit
import CopyPalCore
import CopyPalServices
import CopyPalStorage
import CopyPalSystem

/// End-to-end check of CopyPal with simulated key presses and real pasteboard writes,
/// for CI and for a quick check on any Mac: `CopyPal.app/Contents/MacOS/CopyPal --self-test`.
/// Uses a temporary history and its own settings; it does write the system clipboard.
///
/// Opens a window with a text field, posts real keyboard events (no CopyPal marker,
/// so the event tap treats them like hardware) and checks what lands in the text and
/// in the history. Exit code: 0 all passed, 1 a check failed, 2 the event tap is
/// unavailable here (no Accessibility permission), 3 timeout.
@MainActor
final class SelfTestRunner {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--self-test")
    }

    private let app: AppController
    private var window: NSWindow?
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
    private var failures = 0
    /// Checks that need something this machine lacks (a permission); never silent.
    private var skipped = 0
    private let pasteKey: UInt16
    private let secretMarker = "SelbsttestGeheimwort\(Int.random(in: 1_000...9_999))"

    init(app: AppController) {
        self.app = app
        pasteKey = app.input.layout.pasteKeyCode
    }

    func run() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 240) {
            Self.write("✘ Zeitüberschreitung nach 240 s")
            exit(3)
        }
        Task { @MainActor in
            let code = await runAll()
            exit(code)
        }
    }

    // MARK: Scenarios

    private func runAll() async -> Int32 {
        Self.write("CopyPal Selbsttest – \(AppInfo.buildEnvironment) – macOS \(AppInfo.osVersion)")
        // A regular app can be brought to the front (in CI by System Events); the
        // simulated ⌘V must reach this app's text field, not another app.
        NSApp.setActivationPolicy(.regular)
        setUpWindow()
        let active = await waitUntil(timeout: 15_000) {
            NSApp.activate()
            return NSApp.isActive
        }
        Self.write(active ? "CopyPal ist aktiv." : "CopyPal wurde nicht aktiv – \(focusState)")
        focusTextView()
        await sleep(300)
        Self.write("Fokus: \(focusState)")

        await captureChecks()

        // InputCoordinator starts the tap as soon as Accessibility is granted (≤ 2 s).
        let tapReady = await waitUntil(timeout: 3_000) { self.app.input.tap.isRunning && self.app.input.tap.isEnabled }
        guard tapReady else {
            Self.write("Event-Tap nicht verfügbar (Bedienungshilfen: \(AccessibilityPermission.state == .granted ? "erteilt" : "nicht erteilt")).")
            Self.write(failures == 0 ? "Erfassen bestanden; Tastatur-Prüfungen übersprungen." : "\(failures) Prüfung(en) fehlgeschlagen.")
            return failures == 0 ? 2 : 1
        }
        app.input.tap.diagnostics.isRecording = true
        Self.write(String(format: "Event-Tap läuft · ⌘V-Taste %ld · Halteschwelle %.2f s", Int(pasteKey), AppSettings.holdThreshold))

        await gestureChecks()
        await popupChecks()
        await screenshotChecks()
        await robustnessChecks()
        await performanceChecks()

        if let popup = app.input.tap.diagnostics.snapshot().popup {
            Self.write(String(format: "Messwert Pop-up-Latenz: Median %.0f ms · p90 %.0f ms (n = %ld)", popup.median, popup.p90, popup.count))
        }
        Self.write(summaryLine)
        return failures == 0 ? 0 : 1
    }

    private var summaryLine: String {
        if failures > 0 { return "\(failures) Prüfung(en) fehlgeschlagen." }
        return skipped > 0 ? "Alle Prüfungen bestanden (\(skipped) übersprungen)." : "Alle Prüfungen bestanden."
    }

    /// M11: the screenshot hot key, its permission gate, the ⌘V gesture afterwards and
    /// the capture into the history. Capture checks need Screen Recording; without it
    /// they are skipped with a warning, never passed silently.
    private func screenshotChecks() async {
        await check("Tastenkürzel ⌘⇧A ist registriert") {
            let registered = self.app.screenshotHotKey.shortcut == AppSettings.screenshotHotKey
            let available = self.app.screenshot.hotKeyAvailable
            return (registered && available, "registriert: \(registered), frei: \(available)")
        }

        await prepare(clipboard: nil)
        let askedBefore = AppSettings.screenshotPermissionAsked
        await press(0, flags: [.maskCommand, .maskShift])
        let appeared = await waitUntil(timeout: 5_000) {
            self.app.screenshot.isOverlayVisible || self.app.screenshot.isShowingPermissionHint
        }
        if !appeared, app.screenshot.isActive {
            // The frozen capture is still waiting – on macOS 15 a system dialog about
            // Screen Recording can hold it; nothing the runner can answer.
            app.screenshot.cancel()
            skip("⌘⇧A öffnet die Aufnahme oder den Berechtigungshinweis, Esc schließt", reason: "Aufnahme wartet nach 5 s noch auf macOS (Systemdialog?)")
            focusTextView()
        } else {
            await check("⌘⇧A öffnet die Aufnahme oder den Berechtigungshinweis, Esc schließt") {
                let shown = self.app.screenshot.isOverlayVisible ? "Overlay" : (self.app.screenshot.isShowingPermissionHint ? "Berechtigungsfenster" : "nichts")
                await self.sleep(200)
                await self.press(53, flags: [])
                let closed = await self.waitUntil(timeout: 3_000) {
                    !self.app.screenshot.isActive && !self.app.screenshot.isShowingPermissionHint
                }
                // Never asks macOS for the permission on its own.
                let notAsked = AppSettings.screenshotPermissionAsked == askedBefore
                if !closed {
                    self.app.screenshot.cancel()
                    self.app.screenshot.closePermissionWindow()
                }
                self.focusTextView()
                await self.sleep(300)
                let untouched = self.textView.string.isEmpty
                return (appeared && closed && notAsked && untouched, "gezeigt: \(shown), geschlossen: \(closed), nicht selbst angefragt: \(notAsked), Text unverändert: \(untouched)")
            }
        }

        await check("Nach dem Bildschirmfoto fügt ⌘V kurz genau einmal ein") {
            await self.quickTap(repeats: 1, clipboard: "Nach dem Bildschirmfoto")
        }

        if appeared, ScreenCapturePermission.state == .granted {
            await check("⌘⇧A über einem Vollbild-Fenster zeigt die Aufnahme auf diesem Space") {
                let result = await self.inFullScreen { await self.screenshotInFullScreen() }
                return result ?? (true, "übersprungen: kein Vollbild auf diesem Mac")
            }
        }

        await check("Scroll-Zusammenfügen auf synthetischen Bildern") {
            let document = Self.syntheticDocument(width: 240, height: 900)
            let frames = [0, 180, 360].map { document.cropped(PixelRect(x: 0, y: $0, width: 240, height: 360)) }
            var session = ScrollSession(firstFrame: frames[0], scale: 1)
            let first = session.accept(frames[1], direction: .down)
            let second = session.accept(frames[2], direction: .down)
            let height = session.composite().height
            return (height == 720 && session.info.sections == 2, "Höhe \(height) px (erwartet 720), Schritte: \(first), \(second)")
        }

        guard ScreenCapturePermission.state == .granted else {
            skip("Bereich landet als Bild im Verlauf und als PNG + TIFF in der Zwischenablage", reason: "Bildschirmaufnahme auf diesem Rechner nicht erlaubt")
            return
        }
        guard let window else { return }
        let rect = window.frame.insetBy(dx: 20, dy: 20)
        let result = await app.screenshot.captureForSelfTest(rect: rect)
        switch result {
        case .permissionDenied:
            skip("Bereich landet als Bild im Verlauf und als PNG + TIFF in der Zwischenablage", reason: "ScreenCaptureKit verweigert die Aufnahme trotz Freigabe")
        case let .stored(item):
            await check("Bereich landet als Bild im Verlauf und als PNG + TIFF in der Zwischenablage") {
                let scale = self.window?.backingScaleFactor ?? 2
                let expectedWidth = Int((rect.width * scale).rounded())
                let width = item.preview.imageSize?.width ?? 0
                let types = NSPasteboard.general.types?.map(\.rawValue) ?? []
                let onPasteboard = types.contains(PasteboardTypeID.png) && types.contains(PasteboardTypeID.tiff)
                let isTop = self.app.history.items.first?.id == item.id
                let passed = item.kind == .image && abs(width - expectedWidth) <= 2 && onPasteboard && isTop
                return (passed, "Art: \(item.kind.rawValue), Breite \(width) px (erwartet \(expectedWidth)), PNG+TIFF: \(onPasteboard), oben im Verlauf: \(isTop)")
            }
        case let .pasteboardOnly(reason):
            await check("Bereich landet als Bild im Verlauf und als PNG + TIFF in der Zwischenablage") {
                (false, "nur in der Zwischenablage: \(reason)")
            }
        case let .failed(message):
            await check("Bereich landet als Bild im Verlauf und als PNG + TIFF in der Zwischenablage") {
                (false, "fehlgeschlagen: \(message)")
            }
        }
    }

    /// Rows of random pixels: every row unique, like text that never repeats.
    private static func syntheticDocument(width: Int, height: Int) -> PixelBuffer {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 255, count: width * height * PixelBuffer.bytesPerPixel)
        for index in bytes.indices where index % PixelBuffer.bytesPerPixel != 3 {
            bytes[index] = UInt8.random(in: 0...255, using: &generator)
        }
        return PixelBuffer(width: width, height: height, bgra: bytes)
    }

    /// M2–M5: what gets recorded, and how.
    private func captureChecks() async {
        await check("Kopie erscheint im Verlauf") {
            await self.copy("Selbsttest Kopie Eins")
            return (self.topTitle == "Selbsttest Kopie Eins", "oben: „\(self.topTitle ?? "–")“")
        }

        await check("Als geheim markierte Kopie wird nicht gespeichert") {
            let before = self.app.history.items.count
            await self.copy("Passwort 123", extra: [PasteboardTypeID.concealed: Data()])
            return (self.app.history.items.count == before && self.topTitle != "Passwort 123", "Einträge: \(before) → \(self.app.history.items.count)")
        }

        await check("Vorübergehend markierte Kopie wird nicht gespeichert") {
            let before = self.app.history.items.count
            await self.copy("Einmal-Link", extra: [PasteboardTypeID.transient: Data()])
            return (self.app.history.items.count == before, "Einträge: \(before) → \(self.app.history.items.count)")
        }

        await check("Doppelte Kopie rückt nach oben statt doppelt") {
            await self.copy("Selbsttest Duplikat")
            await self.copy("Selbsttest Dazwischen")
            let before = self.app.history.items.count
            await self.copy("Selbsttest Duplikat")
            let titles = self.app.history.items.map(\.preview.title)
            let ok = titles.first == "Selbsttest Duplikat" && titles.filter { $0 == "Selbsttest Duplikat" }.count == 1 && titles.count == before
            return (ok, "oben: „\(titles.first ?? "–")“, Einträge: \(before) → \(titles.count)")
        }

        await check("IBAN wird verdeckt gespeichert und läuft ab") {
            await self.copy("DE89 3704 0044 0532 0130 00")
            guard let item = self.app.history.items.first else { return (false, "nichts gespeichert") }
            let masked = item.sensitivity == .iban && item.displayTitle == "DE89 •••• 3000" && item.localOnly
            self.app.timeSource.advance(by: 61)
            _ = try? await self.app.engine.removeExpired()
            await self.app.history.reload()
            let gone = self.app.history.item(id: item.id) == nil
            self.app.timeSource.offset = 0
            return (masked && gone, "verdeckt: \(masked) („\(item.displayTitle)“), nach 61 s gelöscht: \(gone)")
        }

        await check("Ignorierte App wird nicht aufgezeichnet") {
            let before = self.app.history.items.count
            AppSettings.customIgnoredBundleIDs = [Bundle.main.bundleIdentifier ?? ""]
            await self.copy("aus ignorierter App")
            AppSettings.customIgnoredBundleIDs = []
            return (self.app.history.items.count == before, "Einträge: \(before) → \(self.app.history.items.count)")
        }

        await check("Pause verhindert Aufzeichnung") {
            let before = self.app.history.items.count
            self.app.pauseCapture(for: 60)
            await self.copy("während der Pause")
            self.app.resumeCapture()
            await self.copy("nach der Pause")
            return (self.app.history.items.count == before + 1 && self.topTitle == "nach der Pause", "Einträge: \(before) → \(self.app.history.items.count)")
        }

        await check("Bild wird gespeichert, Miniatur entsteht") {
            guard let png = Self.samplePNG() else { return (false, "kein Testbild") }
            await self.copy(nil, extra: [PasteboardTypeID.png: png])
            guard let item = self.app.history.items.first, item.kind == .image else {
                return (false, "oben: \(self.app.history.items.first?.kind.rawValue ?? "–")")
            }
            _ = self.app.visuals.thumbnail(for: item)
            let thumbnail = await self.waitUntil(timeout: 3_000) { self.app.visuals.thumbnails[item.id] != nil }
            return (thumbnail, "Größe: \(item.preview.imageSize.map { "\($0.width)×\($0.height)" } ?? "–"), Miniatur: \(thumbnail)")
        }

        await check("Dateien werden als Verweis gespeichert") {
            let urls = [URL(fileURLWithPath: "/tmp/CopyPal-Selbsttest-A.txt"), URL(fileURLWithPath: "/tmp/CopyPal-Selbsttest-B.pdf")]
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            await self.app.capture.drain()
            let item = self.app.history.items.first
            return (item?.kind == .files && item?.preview.fileNames.count == 2, "oben: \(item?.kind.rawValue ?? "–"), \(item?.preview.fileNames ?? [])")
        }

        await check("Verlauf liegt verschlüsselt auf der Platte") {
            await self.copy("Text mit \(self.secretMarker) darin")
            await self.copy(String(repeating: "\(self.secretMarker) ", count: 8_000))
            let found = Self.files(containing: self.secretMarker, in: self.app.storageDirectory)
            return (found.isEmpty, found.isEmpty ? "kein Klartext gefunden" : "Klartext in: \(found.joined(separator: ", "))")
        }

        await check("Verlauf übersteht einen Neustart") {
            guard let keyStore = self.app.selfTestKeyStore,
                  let reopened = try? ClipStore.open(directory: self.app.storageDirectory, keyStore: keyStore) else {
                return (false, "Speicher ließ sich nicht erneut öffnen")
            }
            let count = (try? reopened.count()) ?? -1
            let expected = self.app.history.items.count
            return (reopened.outcome == .opened && count == expected, "Einträge nach erneutem Öffnen: \(count) (erwartet \(expected))")
        }
    }

    /// M1: the gesture itself.
    private func gestureChecks() async {
        await check("Tippen fügt genau einmal ein") {
            await self.quickTap(repeats: 0, clipboard: "Selbsttest A")
        }

        await check("Tastenwiederholung während des Tippens fügt nur einmal ein") {
            await self.quickTap(repeats: 3, clipboard: "Selbsttest B")
        }

        for (name, flags) in [("⌘⇧V", CGEventFlags([.maskCommand, .maskShift])), ("⌥⌘V", CGEventFlags([.maskCommand, .maskAlternate]))] {
            await check("\(name) wird nicht abgefangen") {
                await self.prepare(clipboard: "")
                await self.press(self.pasteKey, flags: flags)
                await self.sleep(200)
                let decision = self.app.input.tap.diagnostics.snapshot().entries
                    .last { $0.keyCode == self.pasteKey && $0.kind == "↓" }?.decision
                return (decision == "durchgelassen", "Entscheidung: \(decision ?? "–")")
            }
        }
    }

    /// M4/M6: the popup with real entries.
    private func popupChecks() async {
        // Known entries: 8 plain texts, then a bold one on top.
        for index in (2...8).reversed() {
            await copy("Selbsttest Eintrag \(index)")
        }
        await copyBold("Fett formatierter Text")

        await check("Halten öffnet das Pop-up mit den letzten 8 Einträgen") {
            await self.prepare(clipboard: nil)
            await self.openPopup()
            let opened = await self.waitUntil { self.app.popup.isVisible }
            await self.sleep(200)
            let rows = self.app.popup.model.visibleItems.count
            let empty = self.textView.string.isEmpty
            self.app.popup.close()
            return (opened && rows == 8 && empty, "sichtbar: \(opened), Zeilen: \(rows), Text: „\(self.textView.string)“")
        }

        await check("Pop-up erscheint über einem Vollbild-Fenster") {
            await self.fullScreenCheck()
        }

        await check("Klick auf „Favoriten“ neben der Notch wechselt die Liste") {
            await self.favoritesClick(fromTopEdge: false)
        }

        await check("Klick auf „Favoriten“ über einem Vollbild-Fenster, Menüleiste eingeblendet") {
            let result = await self.inFullScreen { () -> (Bool, String) in
                // For comparison only: the level the popup had until the fix.
                let level = self.app.popup.panelLevel
                self.app.popup.panelLevel = .statusBar
                let before = await self.favoritesClick(fromTopEdge: true)
                self.app.popup.panelLevel = level
                let now = await self.favoritesClick(fromTopEdge: true)
                return (now.0, "\(now.1) · zum Vergleich mit Ebene statusBar: \(before.1)")
            }
            return result ?? (true, "übersprungen: kein Vollbild auf diesem Mac")
        }

        await check("Taste 1 fügt formatiert (fett) ein") {
            let result = await self.pasteFromPopup(keys: [(18, [])], expected: "Fett formatierter Text")
            return (result.0 && self.isBold, "\(result.1), fett: \(self.isBold)")
        }

        await check("⇧1 fügt unformatiert ein") {
            let result = await self.pasteFromPopup(keys: [(18, .maskShift)], expected: "Fett formatierter Text")
            return (result.0 && !self.isBold, "\(result.1), fett: \(self.isBold)")
        }

        await check("Taste 3 fügt Eintrag 3 ein, er rückt nach oben") {
            guard self.app.history.items.count >= 3 else { return (false, "zu wenige Einträge") }
            let third = self.app.history.items[2]
            let result = await self.pasteFromPopup(keys: [(20, [])], expected: third.preview.title)
            await self.sleep(200)
            let movedUp = self.app.history.items.first?.id == third.id
            return (result.0 && movedUp && !self.app.popup.isVisible, "\(result.1), oben: „\(self.topTitle ?? "–")“")
        }

        await check("Kurzes ⌘V fügt danach denselben Eintrag ein") {
            let expected = self.topTitle ?? "–"
            await self.prepare(clipboard: nil)
            await self.press(self.pasteKey, flags: .maskCommand, holdFor: 60)
            return await self.expectText(expected)
        }

        await check("Suche „eintrag 5“ und ↩ fügt den Treffer ein") {
            let result = await self.pasteFromPopup(
                keys: Self.typing("eintrag 5") + [(36, [])],
                expected: "Selbsttest Eintrag 5"
            )
            return result
        }

        await check("Esc leert erst die Suche, dann schließt es") {
            await self.prepare(clipboard: nil)
            await self.openPopup()
            _ = await self.waitUntil { self.app.popup.isVisible }
            for (key, flags) in Self.typing("abc") {
                await self.press(key, flags: flags)
            }
            await self.sleep(100)
            let typed = self.app.popup.model.query
            await self.press(53, flags: [])
            await self.sleep(100)
            let cleared = self.app.popup.model.query.isEmpty && self.app.popup.isVisible
            await self.press(53, flags: [])
            let closed = await self.waitUntil { !self.app.popup.isVisible }
            return (typed == "abc" && cleared && closed && self.textView.string.isEmpty, "Suche: „\(typed)“, geleert: \(cleared), geschlossen: \(closed)")
        }

        await check("⌘P macht zum Favoriten, ⇥ zeigt Favoriten, 1 fügt ihn ein") {
            guard let second = self.app.history.items.dropFirst().first else { return (false, "zu wenige Einträge") }
            await self.prepare(clipboard: nil)
            await self.openPopup()
            _ = await self.waitUntil { self.app.popup.isVisible }
            await self.press(125, flags: []) // ↓ to entry 2
            await self.press(35, flags: .maskCommand) // ⌘P
            let pinned = await self.waitUntil { self.app.history.favorites.contains { $0.id == second.id } }
            await self.press(48, flags: []) // ⇥
            await self.sleep(100)
            let showsFavorites = self.app.popup.model.list == .favorites
            await self.press(18, flags: [])
            let result = await self.expectText(second.preview.title)
            return (pinned && showsFavorites && result.0, "angepinnt: \(pinned), Favoritenliste: \(showsFavorites), \(result.1)")
        }

        await check("⌘⌫ löscht den ausgewählten Eintrag") {
            guard let first = self.app.history.items.first else { return (false, "leer") }
            await self.prepare(clipboard: nil)
            await self.openPopup()
            _ = await self.waitUntil { self.app.popup.isVisible }
            await self.press(51, flags: .maskCommand)
            let deleted = await self.waitUntil { self.app.history.item(id: first.id) == nil }
            await self.press(53, flags: [])
            _ = await self.waitUntil { !self.app.popup.isVisible }
            return (deleted, "gelöscht: \(deleted)")
        }

        await check("Kopie vom iPhone: erst Platzhalter, Auswahl lädt den Inhalt") {
            await self.copy("Vom iPhone kopiert (Test)", extra: [PasteboardTypeID.remoteClipboard: Data()])
            let placeholder = self.app.history.items.first?.isRemotePlaceholder == true
            let result = await self.pasteFromPopup(keys: [(18, [])], expected: "Vom iPhone kopiert (Test)", seedClipboard: false)
            let top = self.app.history.items.first
            let stored = top?.origin == .remoteDevice && top?.isRemotePlaceholder == false
            return (placeholder && result.0 && stored, "Platzhalter: \(placeholder), \(result.1), gespeichert: \(stored)")
        }

        await check("Tastenkürzel ⌃⌥V öffnet das Pop-up") {
            await self.prepare(clipboard: nil)
            await self.press(UInt16(9), flags: [.maskControl, .maskAlternate])
            let opened = await self.waitUntil { self.app.popup.isVisible }
            await self.press(53, flags: [])
            _ = await self.waitUntil { !self.app.popup.isVisible }
            return (opened && self.textView.string.isEmpty, "geöffnet: \(opened)")
        }
    }

    /// M8: many quick copies.
    private func robustnessChecks() async {
        await check("100 schnelle Kopien: kein Absturz, keine Duplikate, letzte stimmt") {
            let pasteboard = NSPasteboard.general
            for index in 1...100 {
                pasteboard.clearContents()
                pasteboard.setString("Stress \(index)", forType: .string)
                await self.sleep(100)
            }
            await self.app.capture.drain()
            let titles = self.app.history.items.map(\.preview.title)
            // Only the stress copies count: images from earlier checks share the empty title.
            let stress = titles.filter { $0.hasPrefix("Stress") }
            let duplicates = stress.count - Set(stress).count
            return (titles.first == "Stress 100" && duplicates == 0, "oben: „\(titles.first ?? "–")“, Duplikate: \(duplicates), gespeichert: \(stress.count)")
        }
    }

    /// M8: big copies must not freeze the UI; idle cost and memory are reported.
    private func performanceChecks() async {
        await check("Großes Bild (≈ 20 MB) blockiert die Oberfläche nicht") {
            guard let png = Self.noisePNG(width: 2_600, height: 2_000) else { return (false, "kein Testbild") }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            let meter = StallMeter()
            meter.start()
            await self.app.capture.drain()
            _ = await self.waitUntil(timeout: 5_000) { self.app.history.items.first?.byteSize ?? 0 > 10_000_000 }
            meter.stop()
            let stored = (self.app.history.items.first?.byteSize ?? 0) > 10_000_000
            return (stored && meter.longestStall < 0.25, String(
                format: "%.1f MB gespeichert: %@, längste Blockade des Main-Threads: %.0f ms",
                Double(png.count) / 1_000_000, stored ? "ja" : "nein", meter.longestStall * 1_000
            ))
        }

        let idle = await Self.cpuUsage(during: 5)
        Self.write(String(format: "Messwert CPU im Leerlauf (5 s): %.2f %%", idle * 100))
        Self.write(String(format: "Messwert Speicher: %.0f MB bei %ld Einträgen", Self.memoryFootprint() / 1_000_000, app.history.items.count))
    }

    // MARK: Helpers

    private func check(_ name: String, _ body: () async -> (Bool, String)) async {
        let (passed, detail) = await body()
        if !passed { failures += 1 }
        Self.write("\(passed ? "✔" : "✘") \(name) – \(detail)")
    }

    /// A check this machine cannot run. The `::warning::` line becomes a GitHub
    /// annotation, so a skipped check is never mistaken for a passed one.
    private func skip(_ name: String, reason: String) {
        skipped += 1
        Self.write("⚠︎ \(name) – übersprungen: \(reason)")
        Self.write("::warning::Selbsttest: \(name) übersprungen – \(reason)")
    }

    private var topTitle: String? {
        app.history.items.first?.preview.title
    }

    /// Writes the pasteboard like another app would, then waits until it is processed.
    private func copy(_ text: String?, extra: [String: Data] = [:]) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let text {
            item.setString(text, forType: .string)
        }
        for (type, data) in extra {
            item.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
        pasteboard.writeObjects([item])
        await app.capture.drain()
    }

    private func copyBold(_ text: String) async {
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        let rtf = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        await copy(text, extra: rtf.map { [PasteboardTypeID.rtf: $0] } ?? [:])
    }

    /// The panel must join a full-screen Space (M7). CI can only put CopyPal's own
    /// window into full screen; another app's Space is the manual test in M7.md.
    private func fullScreenCheck() async -> (Bool, String) {
        let result = await inFullScreen { () -> (Bool, String) in
            await self.prepare(clipboard: nil)
            await self.openPopup()
            let opened = await self.waitUntil { self.app.popup.isVisible }
            await self.sleep(200)
            let onSpace = self.app.popup.isOnActiveSpace
            let onScreen = self.app.popup.isOnScreen
            self.app.popup.close()
            await self.sleep(300)
            return (opened && onSpace && onScreen, "sichtbar: \(opened), auf aktivem Space: \(onSpace), auf dem Bildschirm: \(onScreen)")
        }
        return result ?? (true, "übersprungen: kein Vollbild auf diesem Mac")
    }

    /// Runs `body` while the test window is in full screen; nil when this Mac has none.
    private func inFullScreen<Value>(_ body: () async -> Value) async -> Value? {
        guard let window else { return nil }
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.toggleFullScreen(nil)
        guard await waitUntil(timeout: 8_000, { window.styleMask.contains(.fullScreen) }) else {
            return nil
        }
        await sleep(600) // the Space transition
        let result = await body()
        window.toggleFullScreen(nil)
        _ = await waitUntil(timeout: 8_000) { !window.styleMask.contains(.fullScreen) }
        await sleep(600)
        focusTextView()
        return result
    }

    /// Opens the popup and clicks "Favoriten" beside the notch with real mouse events,
    /// routed by the window server like the user's mouse. `fromTopEdge`: the pointer
    /// touches the top edge first, so a menu bar hidden for a full-screen window slides
    /// in – the case where the click used to land on the menu bar.
    private func favoritesClick(fromTopEdge: Bool) async -> (Bool, String) {
        await prepare(clipboard: nil)
        await openPopup()
        guard await waitUntil({ self.app.popup.isVisible }) else { return (false, "Pop-up nicht geöffnet") }
        await sleep(450) // the opening spring
        let point = app.popup.favoritesSwitchPoint
        if fromTopEdge {
            let top = NSScreen.screens.first { $0.frame.contains(point) }?.frame.maxY ?? point.y
            Self.postMouse(.mouseMoved, at: CGPoint(x: point.x, y: top - 1))
            await sleep(1_000)
        }
        Self.postMouse(.mouseMoved, at: point)
        await sleep(150)
        Self.postMouse(.leftMouseDown, at: point)
        await sleep(40)
        Self.postMouse(.leftMouseUp, at: point)
        let switched = await waitUntil(timeout: 1_000) { self.app.popup.model.list == .favorites }
        let open = app.popup.isVisible
        app.popup.close()
        _ = await waitUntil { !self.app.popup.isVisible }
        if let screen = NSScreen.main {
            Self.postMouse(.mouseMoved, at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        }
        await sleep(200)
        return (switched && open, "Favoritenliste: \(switched), Pop-up noch offen: \(open)")
    }

    /// ⌘⇧A over a full-screen window: the overlay must be on that Space (new panels each
    /// session; the first order-in could land on the desktop behind it).
    private func screenshotInFullScreen() async -> (Bool, String) {
        await press(0, flags: [.maskCommand, .maskShift])
        let shown = await waitUntil(timeout: 5_000) { self.app.screenshot.isOverlayVisible }
        let onSpace = app.screenshot.isOverlayOnActiveSpace
        await press(53, flags: [])
        let closed = await waitUntil(timeout: 3_000) { !self.app.screenshot.isActive }
        if !closed {
            app.screenshot.cancel()
        }
        return (shown && onSpace && closed, "sichtbar: \(shown), auf aktivem Space: \(onSpace), Esc schließt: \(closed)")
    }

    private func pasteFromPopup(keys: [(UInt16, CGEventFlags)], expected: String, seedClipboard: Bool = true) async -> (Bool, String) {
        await prepare(clipboard: seedClipboard ? "" : nil)
        await openPopup()
        _ = await waitUntil { self.app.popup.isVisible }
        for (key, flags) in keys {
            await press(key, flags: flags)
        }
        return await expectText(expected)
    }

    /// Key codes of letters that sit on the same keys in US and German layouts.
    private static func typing(_ text: String) -> [(UInt16, CGEventFlags)] {
        let codes: [Character: UInt16] = [
            "a": 0, "b": 11, "c": 8, "e": 14, "g": 5, "i": 34, "n": 45, "r": 15, "t": 17, "5": 23, " ": 49,
        ]
        return text.compactMap { character in
            codes[character].map { code in (code, CGEventFlags()) }
        }
    }

    private func setUpWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 480, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyPal Selbsttest"
        window.isReleasedWhenClosed = false
        textView.isRichText = true
        textView.isEditable = true
        window.contentView = textView
        self.window = window
        focusTextView()
    }

    private func focusTextView() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        _ = window?.makeFirstResponder(textView)
    }

    /// Empties the text field; `clipboard` (if not nil) goes onto the pasteboard as an
    /// ordinary copy first.
    private func prepare(clipboard: String?) async {
        if let clipboard {
            if clipboard.isEmpty {
                NSPasteboard.general.clearContents()
                await app.capture.drain()
            } else {
                await copy(clipboard)
            }
        }
        // Plain text takes on the typing attributes, so a previous bold paste would
        // make the next plain one bold too.
        textView.string = ""
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.textColor]
        focusTextView()
        await sleep(150)
    }

    private func openPopup() async {
        Self.post(pasteKey, down: true, flags: .maskCommand)
        await sleep(Int(AppSettings.holdThreshold * 1000) + 250)
        Self.post(pasteKey, down: false, flags: .maskCommand)
    }

    private var isBold: Bool {
        guard textView.textStorage?.length ?? 0 > 0,
              let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            return false
        }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    private func expectText(_ expected: String) async -> (Bool, String) {
        let matched = await waitUntil { self.textView.string == expected }
        await sleep(250) // a second, unwanted paste would show up now
        let text = textView.string
        let passed = matched && text == expected
        return (passed, passed ? "Text: „\(text)“" : "Text: „\(text)“ (erwartet „\(expected)“) · \(focusState) · Tap: \(recentDecisions)")
    }

    /// Which app and window have the keyboard focus right now.
    private var focusState: String {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let keyWindow = window?.isKeyWindow == true ? "Testfenster" : (NSApp.keyWindow?.title ?? "keins")
        let textFocused = window?.firstResponder === textView
        return "vorne: \(front), CopyPal aktiv: \(NSApp.isActive), Key-Fenster: \(keyWindow), Textfeld fokussiert: \(textFocused)"
    }

    /// The tap's last decisions for the paste key, oldest first.
    private var recentDecisions: String {
        app.input.tap.diagnostics.snapshot().entries
            .filter { $0.keyCode == pasteKey || $0.kind == "Pop-up" }
            .suffix(4)
            .map { "\($0.kind)\($0.isRepeat ? "(Wdh.)" : "") \($0.decision)" }
            .joined(separator: ", ")
    }

    private func waitUntil(timeout milliseconds: Int = 2_000, _ condition: () -> Bool) async -> Bool {
        var waited = 0
        while !condition() {
            if waited >= milliseconds { return false }
            await sleep(25)
            waited += 25
        }
        return true
    }

    private func press(_ keyCode: UInt16, flags: CGEventFlags, holdFor milliseconds: Int = 40) async {
        await Self.postTimed([
            TimedKey(keyCode: keyCode, down: true, flags: flags),
            TimedKey(keyCode: keyCode, down: false, flags: flags, delay: milliseconds),
        ])
        await sleep(30)
    }

    /// A quick ⌘V (with `repeats` autorepeats, 20 ms apart) must paste `clipboard`
    /// exactly once. The events are posted with exact gaps, but a stalled CI machine can
    /// still deliver the ↑ to the tap after the hold threshold: that trial is a hold, not
    /// a tap, and says nothing about the gesture, so it is repeated (at most three tries).
    private func quickTap(repeats: Int, clipboard: String) async -> (Bool, String) {
        let threshold = AppSettings.holdThreshold * 1_000
        var stretched: [String] = []
        for _ in 0..<3 {
            await prepare(clipboard: clipboard)
            let held = await tapPasteKey(repeats: repeats)
            let result = await expectText(clipboard)
            let note = stretched.isEmpty ? "" : " · \(stretched.count)× wiederholt, Runner streckte den Tipp auf \(stretched.joined(separator: ", "))"
            if result.0 {
                return (true, result.1 + note)
            }
            guard let held, held >= threshold * 0.8 else {
                return (false, result.1 + note)
            }
            stretched.append(String(format: "%.0f ms", held))
            if app.popup.isVisible {
                app.popup.close()
            }
            await sleep(300)
        }
        return (false, "Runner zu langsam: jeder Tipp wurde zum Halten (\(stretched.joined(separator: ", ")), Schwelle \(Int(threshold)) ms)")
    }

    /// Posts ⌘V down, `repeats` autorepeats and up, then returns how long the tap saw
    /// the key held (milliseconds), or nil when it did not log the ↑ within a second.
    private func tapPasteKey(repeats: Int) async -> Double? {
        let lastID = app.input.tap.diagnostics.snapshot().entries.last?.id ?? 0
        var keys = [TimedKey(keyCode: pasteKey, down: true, flags: .maskCommand)]
        keys += (0..<repeats).map { _ in TimedKey(keyCode: pasteKey, down: true, flags: .maskCommand, autorepeat: true, delay: 20) }
        keys.append(TimedKey(keyCode: pasteKey, down: false, flags: .maskCommand, delay: 20))
        await Self.postTimed(keys)
        let seen = await waitUntil(timeout: 1_000) { self.heldMilliseconds(after: lastID) != nil }
        return seen ? heldMilliseconds(after: lastID) : nil
    }

    /// Milliseconds between the paste key's first ↓ and its ↑ as the tap logged them,
    /// looking only at entries newer than `id`.
    private func heldMilliseconds(after id: Int) -> Double? {
        let entries = app.input.tap.diagnostics.snapshot().entries.filter { $0.id > id && $0.keyCode == pasteKey }
        guard let down = entries.first(where: { $0.kind == "↓" && !$0.isRepeat }),
              let up = entries.last(where: { $0.kind == "↑" }),
              up.uptime >= down.uptime else {
            return nil
        }
        return (up.uptime - down.uptime) * 1_000
    }

    /// One key event of a timed sequence, posted `delay` milliseconds after the previous one.
    struct TimedKey: Sendable {
        var keyCode: UInt16
        var down: Bool
        var flags: UInt64
        var autorepeat = false
        var delay = 0

        init(keyCode: UInt16, down: Bool, flags: CGEventFlags, autorepeat: Bool = false, delay: Int = 0) {
            self.keyCode = keyCode
            self.down = down
            self.flags = flags.rawValue
            self.autorepeat = autorepeat
            self.delay = delay
        }
    }

    /// Posts the events with exact gaps from a background thread. Sleeping on the main
    /// actor overshoots whenever it is busy (layout, the store), and on a slow CI
    /// machine that once stretched a quick tap past the hold threshold.
    private static func postTimed(_ keys: [TimedKey]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInteractive).async {
                for key in keys {
                    if key.delay > 0 {
                        usleep(useconds_t(key.delay * 1_000))
                    }
                    post(key.keyCode, down: key.down, flags: CGEventFlags(rawValue: key.flags), autorepeat: key.autorepeat)
                }
                continuation.resume()
            }
        }
    }

    /// Posts like a keyboard would: no CopyPal marker, so the tap handles it.
    nonisolated private static func post(_ keyCode: UInt16, down: Bool, flags: CGEventFlags, autorepeat: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else {
            return
        }
        event.flags = flags
        if autorepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        event.post(tap: .cghidEventTap)
    }

    /// Posts like a mouse would; `point` in AppKit coordinates.
    nonisolated private static func postMouse(_ type: CGEventType, at point: CGPoint) {
        // CGEvent coordinates: origin top left of the main display, y down.
        let height = CGDisplayBounds(CGMainDisplayID()).height
        let location = CGPoint(x: point.x, y: height - point.y)
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func sleep(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private static func samplePNG() -> Data? {
        let image = NSImage(size: NSSize(width: 64, height: 32), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return ImageConversion.png(fromImageData: tiff)
    }

    /// Random pixels: a PNG that does not compress (about width × height × 4 bytes).
    private static func noisePNG(width: Int, height: Int) -> Data? {
        var generator = SystemRandomNumberGenerator()
        var words = [UInt64](repeating: 0, count: width * height / 2)
        for index in words.indices {
            words[index] = generator.next()
        }
        let pixels = words.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Share of one CPU core used by CopyPal over `seconds` of waiting.
    private static func cpuUsage(during seconds: Double) async -> Double {
        func cpuTime() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let start = cpuTime()
        try? await Task.sleep(for: .seconds(seconds))
        return (cpuTime() - start) / seconds
    }

    /// Physical memory footprint (what Activity Monitor shows as "Memory").
    private static func memoryFootprint() -> Double {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? Double(info.ri_phys_footprint) : 0
    }

    /// Files below `directory` whose bytes contain `marker`.
    private static func files(containing marker: String, in directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let needle = Data(marker.utf8)
        var found: [String] = []
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            if let data = try? Data(contentsOf: url), data.range(of: needle) != nil {
                found.append(url.lastPathComponent)
            }
        }
        return found
    }

    nonisolated private static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

/// Measures the longest gap between 10 ms timer ticks on the main thread.
@MainActor
private final class StallMeter {
    private(set) var longestStall: TimeInterval = 0
    private var timer: Timer?
    private var lastTick = Date()

    func start() {
        lastTick = Date()
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        tick()
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        longestStall = max(longestStall, now.timeIntervalSince(lastTick))
        lastTick = now
    }
}
#endif
