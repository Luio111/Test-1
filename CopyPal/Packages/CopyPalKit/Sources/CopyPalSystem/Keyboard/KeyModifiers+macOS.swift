#if os(macOS)
import AppKit
import CoreGraphics
import CopyPalCore

extension KeyModifiers {
    public init(_ flags: CGEventFlags) {
        var result: KeyModifiers = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        if flags.contains(.maskAlphaShift) { result.insert(.capsLock) }
        self = result
    }

    public init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.function) { result.insert(.function) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        self = result
    }
}
#endif
