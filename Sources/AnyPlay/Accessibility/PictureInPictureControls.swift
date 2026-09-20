// PictureInPictureControls.swift — operating the system Picture-in-Picture window.
//
// This is the one control path that does not care about window order. A click posted
// to a process never arrives (measured in Phase 0 for Safari and again for the
// Picture-in-Picture window), and a click posted globally lands on whatever is on top
// — the game. The Accessibility API has no such problem: it presses the control in
// the window itself, whether that window is in front, behind a fullscreen game, or on
// another Space.
//
// The buttons are found by their Accessibility identifier, not by their label. Labels
// are translated ("Pause", "10 Sekunden zurückspringen"); identifiers are not.
// Measured on the real window:
//
//   AXWindow "Bild-in-Bild"                    id=picture-in-picture
//     AXButton "Bild-in-Bild schließen"        id=close
//     AXButton "Wiederherstellen"              id=restore
//     AXButton "10 Sekunden zurückspringen"    id=skip-back
//     AXButton "Pause"                         id=pause
//     AXButton "10 Sekunden vorspringen"       id=skip-forward

import AppKit
import ApplicationServices

enum PictureInPictureControl: CaseIterable {
    case playPause
    case back10
    case forward10
    /// Puts the video back into the browser window it came from.
    case restore
    case close

    /// The identifiers this control can carry. The play button is the one that
    /// changes: measured `pause` while the video runs and `play` while it is stopped,
    /// so looking for only one of them finds the button in only one of the two states.
    var identifiers: [String] {
        switch self {
        case .playPause: return ["pause", "play"]
        case .back10:    return ["skip-back"]
        case .forward10: return ["skip-forward"]
        case .restore:   return ["restore"]
        case .close:     return ["close"]
        }
    }

    var logName: String { String(describing: self) }
}

enum PictureInPictureControls {

    static let windowIdentifier = "picture-in-picture"

    /// Presses one control. Returns false if the window or the button is not there —
    /// a Picture-in-Picture window that has been closed in the meantime, for example.
    ///
    /// The buttons only exist while the window shows its controls, and it shows them
    /// while the pointer is over it. So a pointer move is sent first. Measured: a move
    /// posted to the process does arrive and brings the controls up, while a posted
    /// click does not arrive at all — which is exactly why the press goes through the
    /// Accessibility API and not through a click.
    @discardableResult
    static func press(_ control: PictureInPictureControl, inPID pid: pid_t) -> Bool {
        var found = button(control, inPID: pid)
        if found == nil, let window = window(pid: pid) {
            revealControls(of: window, pid: pid)
            found = button(control, inPID: pid)
        }
        guard let button = found else {
            DiagnosticLog.shared?.line("PIP \(control.logName): button not found")
            return false
        }
        let ok = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        DiagnosticLog.shared?.line("PIP \(control.logName) pressed: \(ok)")
        return ok
    }

    /// Moves the pointer over the window so it shows its controls, then waits briefly
    /// for them to appear. The move is posted to the process, so the real pointer on
    /// screen does not jump.
    private static func revealControls(of window: AXUIElement, pid: pid_t) {
        guard let origin = AXBridge.point(window, kAXPositionAttribute as String),
              let extent = AXBridge.size(window, kAXSizeAttribute as String) else { return }
        let centre = CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2)
        InputForwarder.move(to: centre, to: pid)
        // The controls fade in. 250 ms was enough in every run; below 150 ms the
        // buttons were sometimes still missing.
        usleep(250_000)
    }

    /// Whether this process currently owns a Picture-in-Picture window at all.
    static func hasWindow(pid: pid_t) -> Bool { window(pid: pid) != nil }

    private static func window(pid: pid_t) -> AXUIElement? {
        AXBridge.windows(ofPID: pid).first { element in
            AXBridge.string(element, kAXIdentifierAttribute as String) == windowIdentifier
        }
    }

    private static func button(_ control: PictureInPictureControl, inPID pid: pid_t) -> AXUIElement? {
        guard let window = window(pid: pid),
              let children = AXBridge.copy(window, kAXChildrenAttribute as String) as? [AXUIElement]
        else { return nil }
        return children.first { element in
            guard let identifier = AXBridge.string(element, kAXIdentifierAttribute as String)
            else { return false }
            return control.identifiers.contains(identifier)
        }
    }
}
