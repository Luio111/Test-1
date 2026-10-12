#if os(macOS)
import AppKit
import Testing
@testable import CopyPalSystem

/// Uses a private, uniquely named pasteboard so tests never touch the user's clipboard.
@MainActor
struct PasteboardInspectorTests {
    @Test func probeReportsTypesOfPrivatePasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CopyPalTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)

        let probe = PasteboardInspector.probe(pasteboard)
        #expect(probe.changeCount == pasteboard.changeCount)
        #expect(probe.types.contains(NSPasteboard.PasteboardType.string.rawValue))
    }

    @Test func accessStatusResolves() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CopyPalTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        _ = PasteboardInspector.accessStatus(of: pasteboard)
    }
}
#endif
