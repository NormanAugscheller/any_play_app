// MediaKey.swift — the play/pause key on the Mac keyboard, sent by software.
//
// Why this and not a normal key press: the keys AnyPlay used before (K for YouTube)
// belong to the web page, and a page only reacts to keys while it has keyboard focus.
// It gets that from a click, and clicks cannot be delivered to a background app —
// measured in InputForwarder. So the command never arrived reliably.
//
// A media key takes a completely different route. macOS does not send it to the app
// in front but to the app that is currently playing something. That is exactly what
// is needed here: the game keeps focus, the browser gets the command. Verified by
// hand: the physical key pauses a YouTube video in Safari from another app.
//
// Media keys are not key presses in the usual sense either. They arrive as
// system-defined events with their own subtype, and the key is encoded in data1.
// The constants come from Apple's headers, not from guesswork:
//   IOKit/hidsystem/ev_keymap.h   NX_KEYTYPE_PLAY = 16, NEXT = 17, PREVIOUS = 18
//   IOKit/hidsystem/IOLLEvent.h   NX_SUBTYPE_AUX_CONTROL_BUTTONS = 8

import AppKit

enum MediaKey: Int {
    case playPause = 16   // NX_KEYTYPE_PLAY
    case next      = 17   // NX_KEYTYPE_NEXT
    case previous  = 18   // NX_KEYTYPE_PREVIOUS

    var logName: String { String(describing: self) }
}

enum MediaKeySender {

    private static let auxControlButtons: Int16 = 8   // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    /// Sends one press of a media key.
    ///
    /// Posted globally, not to a process: a system-defined event is routed by macOS,
    /// and that routing is the whole point. The consequence is that the command
    /// reaches whatever is playing — if Music is running as well, it may get it
    /// instead of the browser.
    @discardableResult
    static func post(_ key: MediaKey) -> Bool {
        guard let down = event(key, isDown: true), let up = event(key, isDown: false) else {
            DiagnosticLog.shared?.line("MEDIAKEY \(key.logName) could not be built")
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        DiagnosticLog.shared?.line("MEDIAKEY \(key.logName) posted")
        return true
    }

    private static func event(_ key: MediaKey, isDown: Bool) -> CGEvent? {
        // data1 carries the key in the upper half and the up/down state in the lower.
        let state = isDown ? 0x0A : 0x0B
        let data1 = (key.rawValue << 16) | (state << 8)
        return NSEvent.otherEvent(with: .systemDefined,
                                  location: .zero,
                                  modifierFlags: NSEvent.ModifierFlags(rawValue: 0),
                                  timestamp: 0,
                                  windowNumber: 0,
                                  context: nil,
                                  subtype: auxControlButtons,
                                  data1: data1,
                                  data2: -1)?.cgEvent
    }
}
