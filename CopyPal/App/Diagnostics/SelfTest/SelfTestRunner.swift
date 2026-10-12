#if DEBUG
import AppKit
import CopyPalCore
import CopyPalSystem

/// End-to-end check of the ⌘V gesture with simulated key presses, for CI and for a
/// quick check on any Mac: `CopyPal.app/Contents/MacOS/CopyPal --self-test`.
///
/// Opens a window with a text field, posts real keyboard events (no CopyPal marker,
/// so the event tap treats them like hardware) and checks what lands in the text.
/// Exit code: 0 all passed, 1 a check failed, 2 the event tap is unavailable here
/// (no Accessibility permission), 3 timeout.
@MainActor
final class SelfTestRunner {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--self-test")
    }

    private let input: InputCoordinator
    private var window: NSWindow?
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
    private var failures = 0
    private let pasteKey: UInt16

    init(input: InputCoordinator) {
        self.input = input
        pasteKey = input.layout.pasteKeyCode
    }

    func run() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            Self.write("✘ Zeitüberschreitung nach 120 s")
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
        setUpWindow()
        await sleep(800)

        // InputCoordinator starts the tap as soon as Accessibility is granted (≤ 2 s).
        let tapReady = await waitUntil(timeout: 3_000) { self.input.tap.isRunning && self.input.tap.isEnabled }
        guard tapReady else {
            Self.write("Event-Tap nicht verfügbar (Bedienungshilfen: \(AccessibilityPermission.state == .granted ? "erteilt" : "nicht erteilt")).")
            return 2
        }
        input.tap.diagnostics.isRecording = true
        let threshold = AppSettings.holdThreshold
        Self.write(String(format: "Event-Tap läuft · ⌘V-Taste %ld · Halteschwelle %.2f s", Int(pasteKey), threshold))

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

        await check("Halten öffnet das Pop-up und fügt nichts ein") {
            await self.prepare(clipboard: "darf nicht erscheinen")
            await self.openPopup(threshold: threshold)
            let opened = await self.waitUntil { self.input.popup.isVisible }
            await self.sleep(200)
            let empty = self.textView.string.isEmpty
            self.input.popup.close()
            return (opened && empty, "Pop-up sichtbar: \(opened), Text: „\(self.textView.string)“")
        }

        await check("Taste 3 fügt Eintrag 3 ein und schließt das Pop-up") {
            await self.prepare(clipboard: "")
            await self.openPopup(threshold: threshold)
            _ = await self.waitUntil { self.input.popup.isVisible }
            await self.press(20, flags: []) // key 3
            let result = await self.expectText(PlaceholderClip.all[2].plainText)
            return (result.0 && !self.input.popup.isVisible, result.1)
        }

        await check("Taste 1 fügt formatiert (fett) ein") {
            await self.prepare(clipboard: "")
            await self.openPopup(threshold: threshold)
            _ = await self.waitUntil { self.input.popup.isVisible }
            await self.press(18, flags: [])
            let result = await self.expectText(PlaceholderClip.all[0].plainText)
            return (result.0 && self.isBold, "\(result.1), fett: \(self.isBold)")
        }

        await check("⇧1 fügt unformatiert ein") {
            await self.prepare(clipboard: "")
            await self.openPopup(threshold: threshold)
            _ = await self.waitUntil { self.input.popup.isVisible }
            await self.press(18, flags: .maskShift)
            let result = await self.expectText(PlaceholderClip.all[0].plainText)
            return (result.0 && !self.isBold, "\(result.1), fett: \(self.isBold)")
        }

        await check("Esc schließt das Pop-up ohne Einfügen") {
            await self.prepare(clipboard: "")
            await self.openPopup(threshold: threshold)
            _ = await self.waitUntil { self.input.popup.isVisible }
            await self.press(53, flags: [])
            let closed = await self.waitUntil { !self.input.popup.isVisible }
            await self.sleep(200)
            return (closed && self.textView.string.isEmpty, "geschlossen: \(closed), Text: „\(self.textView.string)“")
        }

        for (name, flags) in [("⌘⇧V", CGEventFlags([.maskCommand, .maskShift])), ("⌥⌘V", CGEventFlags([.maskCommand, .maskAlternate]))] {
            await check("\(name) wird nicht abgefangen") {
                await self.prepare(clipboard: "")
                await self.press(self.pasteKey, flags: flags)
                await self.sleep(200)
                let decision = self.input.tap.diagnostics.snapshot().entries
                    .last { $0.keyCode == self.pasteKey && $0.kind == "↓" }?.decision
                return (decision == "durchgelassen", "Entscheidung: \(decision ?? "–")")
            }
        }

        Self.write(failures == 0 ? "Alle Prüfungen bestanden." : "\(failures) Prüfung(en) fehlgeschlagen.")
        return failures == 0 ? 0 : 1
    }

    // MARK: Helpers

    private func check(_ name: String, _ body: () async -> (Bool, String)) async {
        let (passed, detail) = await body()
        if !passed { failures += 1 }
        Self.write("\(passed ? "✔" : "✘") \(name) – \(detail)")
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

    private func prepare(clipboard: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(clipboard, forType: .string)
        textView.string = ""
        focusTextView()
        await sleep(150)
    }

    private func openPopup(threshold: Double) async {
        post(pasteKey, down: true, flags: .maskCommand)
        await sleep(Int(threshold * 1000) + 250)
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
        return (matched && text == expected, "Text: „\(text)“")
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

    nonisolated private static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
#endif
