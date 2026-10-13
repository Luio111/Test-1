#if DEBUG
import AppKit
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// Lab only (ROADMAP M7): outlines the notch CopyPal computed on every screen, or
/// marks the top center where screens without a notch show the popup.
@MainActor
final class NotchOverlayController {
    private var panels: [NSPanel] = []

    var isVisible: Bool {
        !panels.isEmpty
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        hide()
        for screen in NSScreen.screens {
            let metrics = ScreenMetrics(screen)
            let notch = NotchGeometry.notchRect(on: metrics)
            let frame = notch?.insetBy(dx: -4, dy: -4)
                ?? CGRect(x: metrics.frame.midX - 60, y: metrics.frame.maxY - metrics.menuBarHeight - 4, width: 120, height: metrics.menuBarHeight + 4)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.ignoresMouseEvents = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary]
            let label = notch.map { "Notch \(Int($0.width))×\(Int($0.height)) pt" } ?? "keine Notch – oben mittig"
            panel.contentView = NSHostingView(rootView: NotchOutline(label: label))
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

private struct NotchOutline: View {
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
            .overlay(alignment: .bottom) {
                Text(verbatim: label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.bottom, 1)
            }
    }
}
#endif
