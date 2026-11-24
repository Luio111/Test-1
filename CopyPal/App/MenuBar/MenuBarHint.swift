import AppKit
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// The small card below the menu bar icon while the pointer rests on it: CopyPal's
/// shortcuts at a glance (history popup, screenshot) and what needs attention. Dark
/// like the notch capsules; ignores the mouse and never takes focus.
@MainActor
final class MenuBarHintController {
    private lazy var panel = makePanel()
    private lazy var hosting = NSHostingView(rootView: MenuBarHintView(content: MenuBarHintContent(rows: [], status: nil)))
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// How long the pointer rests on the icon before the card appears.
    static let delay: Duration = .milliseconds(350)

    var isVisible: Bool {
        panel.isVisible
    }

    #if DEBUG
    /// Self-test: where the card is on screen.
    var frame: CGRect {
        panel.frame
    }
    #endif

    /// The pointer arrived on the icon: shows the card below `anchor` (the icon's frame
    /// on screen) after a short rest, with what `content` returns then.
    func schedule(below anchor: @escaping @MainActor () -> (CGRect, NSScreen)?, content: @escaping @MainActor () -> MenuBarHintContent) {
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let self, let place = anchor() else { return }
            self.show(content(), below: place.0, on: place.1)
        }
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        guard panel.isVisible, hideTask == nil else { return }
        animate(to: 0, duration: 0.12)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(130))
            // A cancelled hide was taken over by `show`, which already cleared `hideTask`.
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            self.panel.orderOut(nil)
        }
    }

    private func show(_ content: MenuBarHintContent, below iconFrame: CGRect, on screen: NSScreen) {
        hideTask?.cancel()
        hideTask = nil
        hosting.rootView = MenuBarHintView(content: content)
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        // Centered below the icon, kept on the screen.
        let x = min(max(iconFrame.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = iconFrame.minY - 6 - size.height
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.applyScreenSharingPreference()
            panel.orderFrontOnActiveSpace()
        }
        animate(to: 1, duration: 0.12)
    }

    private func animate(to alpha: CGFloat, duration: TimeInterval) {
        guard AppSettings.animatePopup, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alpha
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .aboveMenuBar
        panel.collectionBehavior = .notchOverlay
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = hosting
        return panel
    }
}

/// What the card shows; plain values, built from the settings when it appears.
struct MenuBarHintContent: Equatable {
    struct Shortcut: Equatable {
        /// "⌘⇧A", as the menu bar writes it.
        var keys: String
        /// "halten" for the ⌘V gesture.
        var suffix: String?
    }

    struct Row: Equatable, Identifiable {
        var id: String
        var title: String
        var shortcuts: [Shortcut]
        /// "aus", "belegt" – instead of or after the shortcuts.
        var note: String?
    }

    var rows: [Row]
    /// Paused or something missing; nil when all is well.
    var status: String?

    /// The shortcuts as set right now.
    @MainActor
    static func current(app: AppController) -> MenuBarHintContent {
        var history: [Shortcut] = []
        if AppSettings.holdGestureEnabled {
            history.append(Shortcut(keys: "⌘V", suffix: String(localized: "halten")))
        }
        if AppSettings.hotKeyEnabled {
            history.append(Shortcut(keys: KeyboardLayout.displayString(for: AppSettings.hotKey)))
        }
        var rows = [
            Row(id: "history", title: String(localized: "Verlauf-Pop-up"), shortcuts: history, note: history.isEmpty ? String(localized: "aus") : nil),
        ]
        if AppSettings.screenshotEnabled {
            rows.append(Row(
                id: "screenshot",
                title: String(localized: "Bildschirmfoto"),
                shortcuts: [Shortcut(keys: KeyboardLayout.displayString(for: AppSettings.screenshotHotKey))],
                note: app.screenshot.hotKeyAvailable ? nil : String(localized: "belegt")
            ))
        }

        let status: String? = if app.needsAttention {
            String(localized: "Berechtigung fehlt – Klick für mehr")
        } else if app.capture.isPaused {
            String(localized: "Aufzeichnung pausiert")
        } else if app.presentation.isActive {
            String(localized: "Präsentationsmodus – Inhalte verborgen")
        } else {
            nil
        }
        return MenuBarHintContent(rows: rows, status: status)
    }

    /// The same for VoiceOver, on the icon itself.
    var spokenText: String {
        let lines = rows.map { row in
            var parts = row.shortcuts.map { shortcut in
                [shortcut.keys, shortcut.suffix].compactMap { $0 }.joined(separator: " ")
            }
            if let note = row.note { parts.append(note) }
            return "\(row.title): \(parts.joined(separator: ", "))"
        }
        return ([status].compactMap { $0 } + lines).joined(separator: ". ")
    }
}

struct MenuBarHintView: View {
    let content: MenuBarHintContent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let status = content.status {
                Label {
                    Text(verbatim: status)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Notch.textPrimary)
                Rectangle()
                    .fill(Theme.Notch.divider)
                    .frame(height: 1)
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.l, verticalSpacing: Theme.Spacing.s) {
                ForEach(content.rows) { row in
                    GridRow {
                        Text(verbatim: row.title)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Notch.textSecondary)
                        shortcuts(of: row)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + Theme.Spacing.xxs)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.Notch.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                        .strokeBorder(Theme.Notch.divider)
                )
        )
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    private func shortcuts(of row: MenuBarHintContent.Row) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(row.shortcuts.enumerated()), id: \.offset) { index, shortcut in
                if index > 0 {
                    Text("oder")
                        .foregroundStyle(Theme.Notch.textSecondary)
                }
                Text(verbatim: shortcut.keys)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Notch.textPrimary)
                    .padding(.horizontal, Theme.Spacing.xs + Theme.Spacing.xxs)
                    .padding(.vertical, 1)
                    .background(Theme.Notch.control, in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
                if let suffix = shortcut.suffix {
                    Text(verbatim: suffix)
                        .foregroundStyle(Theme.Notch.textSecondary)
                }
            }
            if let note = row.note {
                Text(verbatim: note)
                    .foregroundStyle(Theme.Notch.textSecondary)
            }
        }
        .font(.system(size: 12))
    }
}
