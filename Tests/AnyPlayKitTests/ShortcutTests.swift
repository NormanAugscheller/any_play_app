import Testing
import AppKit
import Carbon.HIToolbox
@testable import AnyPlayKit

@Suite("Keyboard shortcuts")
struct ShortcutTests {

    let allFour = UInt32(controlKey | optionKey | cmdKey)

    @Test("The default overlay shortcut reads ⌃⌥⌘P")
    func displaysModifiersInAppleOrder() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: allFour, label: "P")
        #expect(shortcut.display == "⌃⌥⌘P")
    }

    @Test("Shift sits between Option and Command, as in every Apple menu")
    func placesShiftCorrectly() {
        let mods = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        #expect(Shortcut(keyCode: 0, modifiers: mods, label: "A").display == "⌃⌥⇧⌘A")
    }

    @Test("A stored shortcut comes back unchanged")
    func survivesStorage() throws {
        let original = Shortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: allFour, label: "O")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        #expect(decoded == original)
    }

    @Test("A key press without a modifier is rejected")
    func requiresModifier() {
        #expect(Shortcut(keyCode: UInt16(kVK_ANSI_P), modifierFlags: [], characters: "p") == nil)
    }

    @Test("A recorded key press becomes the matching shortcut")
    func buildsFromKeyPress() {
        let shortcut = Shortcut(keyCode: UInt16(kVK_ANSI_O),
                                modifierFlags: [.control, .option, .command],
                                characters: "o")
        #expect(shortcut?.keyCode == UInt32(kVK_ANSI_O))
        #expect(shortcut?.modifiers == allFour)
        #expect(shortcut?.display == "⌃⌥⌘O")
    }

    @Test("A key without printable characters still gets a label")
    func labelsUnprintableKeys() {
        let shortcut = Shortcut(keyCode: UInt16(kVK_F13), modifierFlags: [.command], characters: "")
        #expect(shortcut?.label == "#\(kVK_F13)")
    }
}
