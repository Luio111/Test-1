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
        // ⇧1 produces "!" on QWERTZ – the physical key still counts.
        #expect(PopupKeyMap.action(keyCode: 18, modifiers: .shift, characters: "!") == .select(index: 1, plainText: true))
        #expect(PopupKeyMap.action(keyCode: 36, modifiers: .shift) == .confirm(plainText: true))
    }

    @Test func heldCommandSelectsEvenWhileSearching() {
        #expect(PopupKeyMap.action(keyCode: 19, modifiers: .command) == .select(index: 2, plainText: false))
        #expect(PopupKeyMap.action(keyCode: 19, modifiers: .command, characters: "2", queryIsEmpty: false) == .select(index: 2, plainText: false))
        #expect(PopupKeyMap.action(keyCode: 19, modifiers: [.command, .shift], queryIsEmpty: false) == .select(index: 2, plainText: true))
    }

    @Test func digitsGoIntoSearchOnceTyping() {
        #expect(PopupKeyMap.action(keyCode: 20, modifiers: [], characters: "3", queryIsEmpty: false) == .insertText("3"))
    }

    @Test func navigation() {
        #expect(PopupKeyMap.action(keyCode: 36, modifiers: []) == .confirm(plainText: false))
        #expect(PopupKeyMap.action(keyCode: 76, modifiers: []) == .confirm(plainText: false))
        #expect(PopupKeyMap.action(keyCode: 126, modifiers: []) == .moveUp)
        #expect(PopupKeyMap.action(keyCode: 125, modifiers: []) == .moveDown)
        #expect(PopupKeyMap.action(keyCode: 48, modifiers: []) == .switchList)
        #expect(PopupKeyMap.action(keyCode: 124, modifiers: []) == .showPreview)
        #expect(PopupKeyMap.action(keyCode: 123, modifiers: []) == .hidePreview)
    }

    @Test func escapeClearsSearchFirst() {
        #expect(PopupKeyMap.action(keyCode: 53, modifiers: []) == .cancel)
        #expect(PopupKeyMap.action(keyCode: 53, modifiers: [], queryIsEmpty: false) == .clearQuery)
    }

    @Test func typingSearches() {
        #expect(PopupKeyMap.action(keyCode: 15, modifiers: [], characters: "r") == .insertText("r"))
        #expect(PopupKeyMap.action(keyCode: 15, modifiers: .shift, characters: "R") == .insertText("R"))
        #expect(PopupKeyMap.action(keyCode: 37, modifiers: .option, characters: "@") == .insertText("@"))
        #expect(PopupKeyMap.action(keyCode: 49, modifiers: [], characters: " ") == .insertText(" "))
        #expect(PopupKeyMap.action(keyCode: 15, modifiers: .control, characters: "\u{12}") == nil)
        #expect(PopupKeyMap.action(keyCode: 122, modifiers: [], characters: "\u{F704}") == nil)
    }

    @Test func deleting() {
        #expect(PopupKeyMap.action(keyCode: 51, modifiers: [], queryIsEmpty: false) == .deleteBackward)
        #expect(PopupKeyMap.action(keyCode: 51, modifiers: []) == nil)
        #expect(PopupKeyMap.action(keyCode: 51, modifiers: .command) == .deleteItem)
    }

    @Test func commandShortcuts() {
        #expect(PopupKeyMap.action(keyCode: 35, modifiers: .command, characters: "p", baseCharacters: "p") == .togglePin)
        // ⌘P on a layout where P sits elsewhere: the character decides, not the key.
        #expect(PopupKeyMap.action(keyCode: 15, modifiers: .command, characters: "p", baseCharacters: "p") == .togglePin)
        #expect(PopupKeyMap.action(keyCode: 9, modifiers: .command, characters: "v", baseCharacters: "v") == nil)
    }
}

struct HotKeyShortcutTests {
    @Test func validity() {
        #expect(HotKeyShortcut.standard.isValid)
        #expect(!HotKeyShortcut(keyCode: 9, modifiers: .shift).isValid)
        #expect(!HotKeyShortcut(keyCode: 9, modifiers: .command).isValid)
        #expect(HotKeyShortcut(keyCode: 9, modifiers: [.command, .shift]).isValid)
        #expect(HotKeyShortcut.screenshotStandard.isValid)
    }

    @Test func standardCommandsAreRefused() {
        let command = HotKeyShortcut(keyCode: 6, modifiers: .command)
        for name in ["C", "x", "V", "Z", "A", "Q", "W", "H", "M", "⇥", "Space"] {
            #expect(command.isStandardCommand(keyName: name), "⌘\(name)")
        }
        #expect(!command.isStandardCommand(keyName: "K"))
        #expect(HotKeyShortcut(keyCode: 6, modifiers: [.command, .shift]).isStandardCommand(keyName: "Z"))
        #expect(!HotKeyShortcut.screenshotStandard.isStandardCommand(keyName: "A"))
        #expect(!HotKeyShortcut.standard.isStandardCommand(keyName: "V"))
    }
}
