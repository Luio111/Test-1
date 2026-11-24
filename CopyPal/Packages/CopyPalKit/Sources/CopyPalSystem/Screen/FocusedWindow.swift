#if os(macOS)
import AppKit
import ApplicationServices
import CopyPalCore

/// Where the user is working: the focused window of the frontmost app (through the
/// Accessibility API, which CopyPal has for the event tap anyway).
public enum FocusedWindow {
    /// Frame of `processID`'s focused window in AppKit screen coordinates (origin at
    /// the bottom left of the primary screen), or nil without permission or window.
    @MainActor
    public static func frame(processID: pid_t) -> CGRect? {
        let application = AXUIElementCreateApplication(processID)
        // An app that hangs must not delay the popup.
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let window = element(application, "AXFocusedWindow"),
              let position = point(window, "AXPosition"),
              let size = size(window, "AXSize") else {
            return nil
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: position.x, y: primaryHeight - position.y - size.height, width: size.width, height: size.height)
    }

    /// The screen to show the popup on (ROADMAP M7): the one with the focused window,
    /// else the one with the mouse pointer.
    @MainActor
    public static func screenForPopup(frontmostProcessID: pid_t?) -> NSScreen? {
        let screens = NSScreen.screens
        let windowFrame = frontmostProcessID.flatMap { frame(processID: $0) }
        guard let index = NotchGeometry.screenIndex(
            screens: screens.map(\.frame),
            keyWindowFrame: windowFrame,
            mouseLocation: NSEvent.mouseLocation
        ) else {
            return NSScreen.main
        }
        return screens[index]
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(element, attribute), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(element, attribute), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }
}
#endif
