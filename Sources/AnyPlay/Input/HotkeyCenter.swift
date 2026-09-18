// HotkeyCenter.swift — global keyboard shortcuts.
//
// RegisterEventHotKey rather than an NSEvent monitor: a monitor only watches an
// event go by, a registered hotkey swallows it. That is needed here so the game does
// not receive the combination as well. Measured with two fullscreen games: eight
// shortcut presses out of eight arrived, none was intercepted by the game.

import AppKit
import Carbon.HIToolbox
import AnyPlayKit

/// What a shortcut can trigger.
enum HotkeyAction: String, CaseIterable {
    case toggleOverlay
    case toggleMode
    case playPause

    var label: String {
        L10n.tr("hotkey.\(rawValue)")
    }

    var defaultShortcut: Shortcut {
        // Control, Option and Command together are used by practically no app or game.
        let mods = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .toggleOverlay: return Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: mods, label: "P")
        case .toggleMode:    return Shortcut(keyCode: UInt32(kVK_ANSI_I), modifiers: mods, label: "I")
        case .playPause:     return Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: mods, label: "K")
        }
    }
}

/// Carbon's C callback cannot carry an object, hence a file-level reference to the
/// one center.
private var activeCenter: HotkeyCenter?

private func hotkeyCallback(_ handlerCall: EventHandlerCallRef?,
                            _ event: EventRef?,
                            _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    if let event {
        GetEventParameter(event, EventParamName(kEventParamDirectObject),
                          EventParamType(typeEventHotKeyID), nil,
                          MemoryLayout<EventHotKeyID>.size, nil, &id)
    }
    MainActor.assumeIsolated { activeCenter?.fired(id: id.id) }
    return noErr
}

@MainActor
final class HotkeyCenter {

    static let shared = HotkeyCenter()

    var onAction: ((HotkeyAction) -> Void)?

    private var registered: [HotkeyAction: EventHotKeyRef] = [:]
    private var installedHandler = false
    private let defaults = UserDefaults.standard

    private init() { activeCenter = self }

    // MARK: Bindings

    func shortcut(for action: HotkeyAction) -> Shortcut {
        guard let data = defaults.data(forKey: Self.key(action)),
              let stored = try? JSONDecoder().decode(Shortcut.self, from: data)
        else { return action.defaultShortcut }
        return stored
    }

    func setShortcut(_ shortcut: Shortcut, for action: HotkeyAction) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Self.key(action))
        }
        register(action)
    }

    func resetToDefaults() {
        for action in HotkeyAction.allCases {
            defaults.removeObject(forKey: Self.key(action))
            register(action)
        }
    }

    private static func key(_ action: HotkeyAction) -> String {
        "hotkey." + action.rawValue
    }

    // MARK: Registration

    /// Removes every registration. Needed while a new shortcut is being recorded: a
    /// registered hotkey swallows the key press, so it would never reach the recorder.
    func unregisterAll() {
        for (action, ref) in registered {
            UnregisterEventHotKey(ref)
            registered[action] = nil
        }
    }

    func registerAll() {
        installHandlerIfNeeded()
        for action in HotkeyAction.allCases { register(action) }
    }

    private func installHandlerIfNeeded() {
        guard !installedHandler else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, 1, &spec, nil, nil)
        DiagnosticLog.shared?.line("HOTKEY InstallEventHandler → \(status)")
        installedHandler = (status == noErr)
    }

    private func register(_ action: HotkeyAction) {
        if let existing = registered[action] {
            UnregisterEventHotKey(existing)
            registered[action] = nil
        }
        let shortcut = shortcut(for: action)
        let id = EventHotKeyID(signature: OSType(0x414E5059) /* ANPY */,
                               id: UInt32(HotkeyAction.allCases.firstIndex(of: action) ?? 0) + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            registered[action] = ref
        }
        DiagnosticLog.shared?.line("HOTKEY \(action.rawValue) = \(shortcut.display) → \(status)")
    }

    fileprivate func fired(id: UInt32) {
        let index = Int(id) - 1
        guard index >= 0, index < HotkeyAction.allCases.count else { return }
        let action = HotkeyAction.allCases[index]
        DiagnosticLog.shared?.line("HOTKEY FIRED \(action.rawValue) "
            + "(front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"))")
        onAction?(action)
    }
}
