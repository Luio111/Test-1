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
        await robustnessChecks()
        await performanceChecks()

        if let popup = app.input.tap.diagnostics.snapshot().popup {
            Self.write(String(format: "Messwert Pop-up-Latenz: Median %.0f ms · p90 %.0f ms (n = %ld)", popup.median, popup.p90, popup.count))
        }
        Self.write(failures == 0 ? "Alle Prüfungen bestanden." : "\(failures) Prüfung(en) fehlgeschlagen.")
        return failures == 0 ? 0 : 1
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
            await self.prepare(clipboard: "Selbsttest A")
            await self.press(self.pasteKey, flags: .maskCommand, holdFor: 60)
            return await self.expectText("Selbsttest A")
        }

        await check("Tastenwiederholung während des Tippens fügt nur einmal ein") {
            await self.prepare(clipboard: "Selbsttest B")
            self.post(self.pasteKey, down: true, flags: .maskCommand)
            for _ in 0..<3 {
                await self.sleep(30)
                self.post(self.pasteKey, down: true, flags: .maskCommand, autorepeat: true)
            }
            await self.sleep(30)
            self.post(self.pasteKey, down: false, flags: .maskCommand)
            return await self.expectText("Selbsttest B")
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
            let duplicates = titles.count - Set(titles).count
            return (titles.first == "Stress 100" && duplicates == 0, "oben: „\(titles.first ?? "–")“, Duplikate: \(duplicates), gespeichert: \(titles.filter { $0.hasPrefix("Stress") }.count)")
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
        post(pasteKey, down: true, flags: .maskCommand)
        await sleep(Int(AppSettings.holdThreshold * 1000) + 250)
        post(pasteKey, down: false, flags: .maskCommand)
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
        post(keyCode, down: true, flags: flags)
        await sleep(milliseconds)
        post(keyCode, down: false, flags: flags)
        await sleep(30)
    }

    /// Posts like a keyboard would: no CopyPal marker, so the tap handles it.
    private func post(_ keyCode: UInt16, down: Bool, flags: CGEventFlags, autorepeat: Bool = false) {
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
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) : 0
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
