import AppKit
import CopyPalSystem

/// The menu bar icon and its menu. Kept short: CopyPal is used through ⌘V; the menu
/// is for the history window, pausing, settings and help. The icon shows a pause
/// or a warning (missing permission) at a glance.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    enum Status: Equatable {
        case normal
        case paused
        case needsAttention
    }

    private let statusItem: NSStatusItem
    private unowned let app: AppController

    init(app: AppController) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        update()
    }

    /// Re-reads the state for the icon (pause, warnings).
    func update() {
        let status: Status = if app.needsAttention {
            .needsAttention
        } else if app.capture.isPaused {
            .paused
        } else {
            .normal
        }
        guard let button = statusItem.button else { return }
        let (symbol, description) = switch status {
        case .normal: ("doc.on.clipboard", String(localized: "CopyPal"))
        case .paused: ("pause.circle", String(localized: "CopyPal – Aufzeichnung pausiert"))
        case .needsAttention: ("exclamationmark.triangle", String(localized: "CopyPal – Berechtigung fehlt"))
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.toolTip = description
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: String(localized: "CopyPal \(AppInfo.version)"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if app.input.permission == .denied {
            menu.addItem(.separator())
            menu.addItem(makeItem(String(localized: "Bedienungshilfen erneut erteilen …"), symbol: "exclamationmark.triangle") { app in
                app.requestAccessibility()
            })
        }
        if app.capture.blockedReason == .accessDenied {
            menu.addItem(makeItem(String(localized: "Zugriff auf die Zwischenablage erlauben …"), symbol: "exclamationmark.triangle") { app in
                app.openPasteboardPrivacySettings()
            })
        }
        if let problem = app.storageProblem {
            let item = NSMenuItem(title: problem, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if app.screenshot.permissionRevoked {
            menu.addItem(makeItem(String(localized: "Bildschirmaufnahme erlauben …"), symbol: "exclamationmark.triangle") { app in
                app.screenshot.showPermissionWindow()
            })
        }

        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Verlauf öffnen"), keyEquivalent: "") { app in
            app.showHistoryWindow()
        })
        if AppSettings.screenshotEnabled {
            menu.addItem(screenshotItem())
        }
        menu.addItem(pauseItem())
        menu.addItem(makeItem(String(localized: "Verlauf löschen …")) { app in
            app.confirmClearHistory()
        })

        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Einstellungen …"), keyEquivalent: ",") { app in
            app.showSettings()
        })
        if app.updates.isAvailable {
            menu.addItem(makeItem(String(localized: "Nach Updates suchen …")) { app in
                app.updates.checkForUpdates()
            })
        }
        menu.addItem(makeItem(String(localized: "Diagnose …")) { app in
            app.showDiagnostics()
        })
        #if DEBUG
        menu.addItem(debugItem())
        #endif

        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "CopyPal beenden"), keyEquivalent: "q") { _ in
            NSApp.terminate(nil)
        })
    }

    /// „Bildschirmfoto aufnehmen“ with the shortcut shown the way the menu bar shows
    /// it; the Carbon hot key does the actual work, the menu is the second way in.
    private func screenshotItem() -> NSMenuItem {
        let shortcut = AppSettings.screenshotHotKey
        let keyName = KeyboardLayout.keyName(for: shortcut.keyCode)
        let keyEquivalent = keyName.count == 1 ? keyName.lowercased() : ""
        let item = makeItem(String(localized: "Bildschirmfoto aufnehmen"), symbol: "camera.viewfinder", keyEquivalent: keyEquivalent) { app in
            app.screenshot.start()
        }
        if !keyEquivalent.isEmpty {
            var mask: NSEvent.ModifierFlags = []
            if shortcut.modifiers.contains(.command) { mask.insert(.command) }
            if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
            if shortcut.modifiers.contains(.option) { mask.insert(.option) }
            if shortcut.modifiers.contains(.control) { mask.insert(.control) }
            item.keyEquivalentModifierMask = mask
        }
        return item
    }

    private func pauseItem() -> NSMenuItem {
        if app.capture.isPaused {
            let until = AppSettings.pausedUntil
            let title: String
            if let until, until < Date.distantFuture.addingTimeInterval(-86_400) {
                let time = until.formatted(date: .omitted, time: .shortened)
                title = String(localized: "Aufzeichnung fortsetzen (pausiert bis \(time))")
            } else {
                title = String(localized: "Aufzeichnung fortsetzen")
            }
            return makeItem(title, symbol: "play.circle") { app in
                app.resumeCapture()
            }
        }
        let item = NSMenuItem(title: String(localized: "Aufzeichnung pausieren"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.addItem(makeItem(String(localized: "15 Minuten")) { app in app.pauseCapture(for: 15 * 60) })
        submenu.addItem(makeItem(String(localized: "1 Stunde")) { app in app.pauseCapture(for: 3_600) })
        submenu.addItem(makeItem(String(localized: "Bis zur Reaktivierung")) { app in app.pauseCapture(for: nil) })
        item.submenu = submenu
        return item
    }

    #if DEBUG
    private func debugItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Entwicklung"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(makeItem(String(localized: "Labor …")) { app in app.showLab() })
        submenu.addItem(makeItem(String(localized: "Onboarding zeigen …")) { app in app.showOnboarding() })
        submenu.addItem(.separator())
        let offsetDays = Int((app.timeSource.offset / 86_400).rounded())
        let offsetItem = NSMenuItem(title: String(localized: "Zeitversatz: \(offsetDays) Tage"), action: nil, keyEquivalent: "")
        offsetItem.isEnabled = false
        submenu.addItem(offsetItem)
        submenu.addItem(makeItem(String(localized: "Zeit +1 Tag")) { app in app.advanceTime(days: 1) })
        submenu.addItem(makeItem(String(localized: "Zeit +2 Tage")) { app in app.advanceTime(days: 2) })
        submenu.addItem(makeItem(String(localized: "Zeit +31 Tage")) { app in app.advanceTime(days: 31) })
        submenu.addItem(makeItem(String(localized: "Zeitversatz zurücksetzen")) { app in app.resetTimeOffset() })
        item.submenu = submenu
        return item
    }
    #endif

    // MARK: Items

    private func makeItem(
        _ title: String,
        symbol: String? = nil,
        keyEquivalent: String = "",
        action: @escaping @MainActor (AppController) -> Void
    ) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: keyEquivalent) { [weak self] in
            guard let self else { return }
            action(self.app)
        }
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }
}

/// A menu item that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func run() {
        handler()
    }
}
