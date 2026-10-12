import Testing
@testable import CopyPalCore

struct PopupKeyMapTests {
    @Test(arguments: [(18, 1), (19, 2), (20, 3), (21, 4), (23, 5), (22, 6), (26, 7), (28, 8)] as [(UInt16, Int)])
    func numberRowSelects(keyCode: UInt16, index: Int) {
        #expect(PopupKeyMap.action(keyCode: keyCode, modifiers: []) == .select(index: index, plainText: false))
    }

    @Test func keypadSelects() {
        #expect(PopupKeyMap.action(keyCode: 83, modifiers: []) == .select(index: 1, plainText: false))
        #expect(PopupKeyMap.action(keyCode: 91, modifiers: []) == .select(index: 8, plainText: false))
    }

    @Test func shiftMeansPlainText() {
        #expect(PopupKeyMap.action(keyCode: 18, modifiers: .shift) == .select(index: 1, plainText: true))
        #expect(PopupKeyMap.action(keyCode: 36, modifiers: .shift) == .confirm(plainText: true))
    }

    @Test func heldCommandDoesNotChangeSelection() {
        #expect(PopupKeyMap.action(keyCode: 19, modifiers: .command) == .select(index: 2, plainText: false))
    }

    @Test func navigationAndCancel() {
        #expect(PopupKeyMap.action(keyCode: 53, modifiers: []) == .cancel)
        #expect(PopupKeyMap.action(keyCode: 36, modifiers: []) == .confirm(plainText: false))
        #expect(PopupKeyMap.action(keyCode: 76, modifiers: []) == .confirm(plainText: false))
        #expect(PopupKeyMap.action(keyCode: 126, modifiers: []) == .moveUp)
        #expect(PopupKeyMap.action(keyCode: 125, modifiers: []) == .moveDown)
    }

    @Test(arguments: [25 as UInt16, 29, 9, 0, 49])
    func otherKeysAreIgnored(keyCode: UInt16) {
        // 9 (key 9), 0 (key 0), V, A, space
        #expect(PopupKeyMap.action(keyCode: keyCode, modifiers: []) == nil)
    }
}
