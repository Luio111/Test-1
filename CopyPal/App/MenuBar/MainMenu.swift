import AppKit

/// Invisible main menu. An accessory app never shows it, but AppKit routes ⌘ shortcuts
/// (⌘C, ⌘A, ⌘W, ⌘Q) through it; without it they do nothing in CopyPal's windows.
/// All targets are nil so the responder chain handles the actions.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("CopyPal", items: [
            NSMenuItem(title: String(localized: "CopyPal beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu(String(localized: "Bearbeiten"), items: [
            NSMenuItem(title: String(localized: "Ausschneiden"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: String(localized: "Kopieren"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: String(localized: "Einsetzen"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: String(localized: "Alles auswählen"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        menu.addItem(submenu(String(localized: "Fenster"), items: [
            NSMenuItem(title: String(localized: "Schließen"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        return menu
    }

    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        for item in items {
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
