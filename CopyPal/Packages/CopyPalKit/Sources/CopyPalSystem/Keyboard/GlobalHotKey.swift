#if os(macOS)
import Carbon
import CopyPalCore

extension HotKeyShortcut {
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}

/// System-wide hotkey through Carbon's `RegisterEventHotKey`. Works without the
/// Accessibility permission (unlike the event tap), so the popup stays reachable.
@MainActor
public final class GlobalHotKey {
    public var onPress: (() -> Void)?
    public private(set) var shortcut: HotKeyShortcut?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4370_506C // "CpPl"

    public init() {}

    /// Registers `shortcut` (replacing the previous one); nil unregisters. Returns false
    /// when macOS refuses, e.g. because another app owns the combination.
    @discardableResult
    public func register(_ shortcut: HotKeyShortcut?) -> Bool {
        unregister()
        guard let shortcut, shortcut.isValid else { return shortcut == nil }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        self.shortcut = shortcut
        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        shortcut = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                // Carbon delivers application-target events on the main thread.
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    hotKey.onPress?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
    }
}
#endif
