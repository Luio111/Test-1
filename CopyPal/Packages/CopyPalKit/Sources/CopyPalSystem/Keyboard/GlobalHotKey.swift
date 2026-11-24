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
/// Each instance is one hotkey (popup, screenshot …); they share one event handler.
@MainActor
public final class GlobalHotKey {
    public var onPress: (() -> Void)?
    public private(set) var shortcut: HotKeyShortcut?

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32
    private static let signature: OSType = 0x4370_506C // "CpPl"
    private static var nextID: UInt32 = 1
    private static var handlerRef: EventHandlerRef?
    /// Live instances by id; the Carbon callback looks up which hotkey was pressed.
    private static var instances: [UInt32: GlobalHotKey] = [:]

    public init() {
        id = Self.nextID
        Self.nextID += 1
    }

    /// Registers `shortcut` (replacing the previous one); nil unregisters. Returns false
    /// when macOS refuses, e.g. because another app owns the combination.
    @discardableResult
    public func register(_ shortcut: HotKeyShortcut?) -> Bool {
        unregister()
        guard let shortcut, shortcut.isValid else { return shortcut == nil }
        Self.installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == OSStatus(noErr), let ref else { return false }
        hotKeyRef = ref
        self.shortcut = shortcut
        Self.instances[id] = self
        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        shortcut = nil
        Self.instances[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == OSStatus(noErr) else { return OSStatus(eventNotHandledErr) }
                // Carbon delivers application-target events on the main thread. The type
                // is named in full: a C function pointer cannot capture `Self`.
                return MainActor.assumeIsolated {
                    guard hotKeyID.signature == GlobalHotKey.signature,
                          let hotKey = GlobalHotKey.instances[hotKeyID.id] else {
                        return OSStatus(eventNotHandledErr)
                    }
                    hotKey.onPress?()
                    return OSStatus(noErr)
                }
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}
#endif
