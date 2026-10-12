import AppKit
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// Short status capsule at the notch ("Copied ✓", "Press ⌘V now"). On a Mac with a
/// notch it looks like the notch briefly grows; elsewhere it hangs below the menu bar.
/// Ignores the mouse and never takes focus.
@MainActor
final class ToastController {
    private let model = ToastModel()
    private lazy var panel = makePanel()
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, systemImage: String, duration: Duration = .milliseconds(1_300)) {
        model.text = text
        model.systemImage = systemImage

        let screen = FocusedWindow.screenForPopup(frontmostProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
            ?? NSScreen.main
        guard let screen else { return }
        let metrics = ScreenMetrics(screen)
        model.notchHeight = NotchGeometry.notchRect(on: metrics)?.height ?? 0
        let contentSize = NSSize(width: ToastView.width(for: text), height: ToastView.height)
        panel.setFrame(NotchGeometry.hudFrame(size: contentSize, on: metrics), display: true)

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )

        hideTask?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        animate(to: 1, duration: 0.12)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.animate(to: 0, duration: 0.2)
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
        }
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
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: ToastView(model: model))
        return panel
    }
}

@MainActor
@Observable
final class ToastModel {
    var text = ""
    var systemImage = "checkmark"
    /// Height of the notch the capsule extends (0 without notch).
    var notchHeight: CGFloat = 0
}

struct ToastView: View {
    static let height: CGFloat = 30

    static func width(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth) + 64
    }

    let model: ToastModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: model.notchHeight)
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: model.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(verbatim: model.text)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity)
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: model.notchHeight > 0 ? 0 : Self.height / 2,
                bottomLeadingRadius: Self.height / 2,
                bottomTrailingRadius: Self.height / 2,
                topTrailingRadius: model.notchHeight > 0 ? 0 : Self.height / 2
            )
            .fill(Color.black)
        )
    }
}
