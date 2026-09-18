// Shortcut.swift — a global keyboard shortcut as it is stored and shown.

import AppKit
import Carbon.HIToolbox

public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier flags, as RegisterEventHotKey expects them.
    public var modifiers: UInt32
    /// Printed name of the key, stored when the shortcut is recorded. Deriving it from
    /// the key code alone needs a table that is wrong for half the keyboard layouts.
    public var label: String

    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    /// Readable form for the interface, e.g. "⌃⌥⌘P".
    public var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { text += "⌘" }
        return text + label
    }

    /// Builds a shortcut from a key press. Without a modifier there is nothing usable:
    /// a system-wide shortcut on a bare key would get in the way everywhere.
    public init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, characters: String?) {
        var carbon: UInt32 = 0
        if modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if modifierFlags.contains(.option)  { carbon |= UInt32(optionKey) }
        if modifierFlags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        guard carbon != 0 else { return nil }
        let text = (characters ?? "").uppercased()
        self.init(keyCode: UInt32(keyCode), modifiers: carbon,
                  label: text.isEmpty ? "#\(keyCode)" : text)
    }
}
