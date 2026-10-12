#if os(macOS)
import AppKit
import CoreGraphics
import Testing
import CopyPalCore
@testable import CopyPalSystem

struct KeyboardTests {
    @Test func markerIdentifiesOwnEvents() throws {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true))
        #expect(!PasteSynthesizer.isOwn(event))
        event.setIntegerValueField(.eventSourceUserData, value: PasteSynthesizer.marker)
        #expect(PasteSynthesizer.isOwn(event))
    }

    @Test func cgEventFlagsMapToModifiers() {
        let modifiers = KeyModifiers(CGEventFlags([.maskCommand, .maskShift, .maskAlphaShift]))
        #expect(modifiers == [.command, .shift, .capsLock])
        #expect(!modifiers.isExactlyCommand)
        #expect(KeyModifiers(CGEventFlags.maskCommand).isExactlyCommand)
    }

    @Test func appKitFlagsMapToModifiers() {
        #expect(KeyModifiers(NSEvent.ModifierFlags([.command, .option])) == [.command, .option])
        #expect(KeyModifiers(NSEvent.ModifierFlags.control) == [.control])
    }

    @Test func pasteKeyResolves() {
        let resolution = KeyboardLayout.resolvePasteKey()
        #expect(resolution.pasteKeyCode < 128)
    }
}
#endif
