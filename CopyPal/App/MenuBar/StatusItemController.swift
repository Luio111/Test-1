import AppKit

/// The menu bar icon and its menu. Kept deliberately short: CopyPal is used through
/// ⌘V, the menu is only for settings, diagnostics and quitting.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onShowDiagnostics: () -> Void
    private let onQuit: () -> Void

    init(onShowDiagnostics: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onShowDiagnostics = onShowDiagnostics
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyPal")
            image?.isTemplate = true
            button.image = image
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: String(localized: "CopyPal \(AppInfo.version)"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Diagnose …"), action: #selector(showDiagnostics)))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "CopyPal beenden"), action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    private func makeItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func showDiagnostics() {
        onShowDiagnostics()
    }

    @objc private func quit() {
        onQuit()
    }
}
