// InputForwarder.swift — sending commands to the target window without switching to it.
//
// The measurement that changed the original plan:
//
//   Mouse clicks and scrolls sent with CGEventPostToPid do NOT reach Safari — zero
//   out of ten attempts across six runs, not even while Safari was active. A regular
//   click at the same spot works, so position and event construction are correct.
//
//   Key presses sent with CGEventPostToPid reach the same app reliably, even in the
//   background.
//
// So in passive mode AnyPlay has no mouse, only commands. To click, switch to input
// mode — the real window lies pixel-exactly beneath the overlay there anyway.
//
// One more distinction matters for everyday use. ⌘T sent to Safari took effect at
// once; the YouTube shortcut K did not, in the same run. The difference is not the
// delivery but the receiver: ⌘T is a command of the application, K belongs to the
// web page, and a page only reacts to keys while it has keyboard focus — which it
// gets from a click, and clicks cannot be sent remotely.

import AppKit
import Carbon.HIToolbox

/// What can be controlled remotely. The keys are the shortcuts YouTube and most web
/// video players understand.
enum RemoteCommand: CaseIterable {
    case playPause
    case back10
    case forward10
    case mute
    case fullscreen

    var keyCode: CGKeyCode {
        switch self {
        case .playPause:  return CGKeyCode(kVK_ANSI_K)
        case .back10:     return CGKeyCode(kVK_ANSI_J)
        case .forward10:  return CGKeyCode(kVK_ANSI_L)
        case .mute:       return CGKeyCode(kVK_ANSI_M)
        case .fullscreen: return CGKeyCode(kVK_ANSI_F)
        }
    }

    /// Only used in the diagnostic log, which is English.
    var logName: String { String(describing: self) }
}

enum InputForwarder {

    /// Sends one key press to one process. Addressing the process is the point: an
    /// event posted globally would go to the game that is in front.
    @discardableResult
    static func send(key: CGKeyCode, flags: CGEventFlags = [], to pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.postToPid(pid)
        // A short pause like a real key stroke; some apps discard a press and release
        // arriving in the same millisecond.
        usleep(60_000)
        up.postToPid(pid)
        return true
    }

    @discardableResult
    static func send(_ command: RemoteCommand, to pid: pid_t) -> Bool {
        send(key: command.keyCode, to: pid)
    }
}
