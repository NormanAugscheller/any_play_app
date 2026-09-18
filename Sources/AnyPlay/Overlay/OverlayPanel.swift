// OverlayPanel.swift — the window that stays on top of everything.
//
// Every setting here was measured, not guessed:
//
// • level .screenSaver (1000) — keeps the panel above a fullscreen game. Verified
//   with two games, four screenshots each.
// • isFloatingPanel BEFORE level — the isFloatingPanel setter sets the level to
//   .floating (3) itself and silently overwrites a level set earlier.
// • canJoinAllSpaces and stationary — otherwise the panel stays behind in the old
//   Space as soon as a game opens its own.
// • nonactivatingPanel — clicking the overlay must not bring AnyPlay forward, or the
//   game loses focus.
// • alphaValue 0.99 and isOpaque false — the most important finding of the whole
//   project: a fully OPAQUE window on top of the target drops the target's frame rate
//   from 57 to 15, because macOS then treats it as covered. At 0.99 the source keeps
//   its full 57. Both properties were changed together in that measurement; which one
//   alone suffices is untested — so both stay.

import AppKit

final class OverlayPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless, .resizable],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        isOpaque = false
        alphaValue = 0.99
        backgroundColor = .black
        hasShadow = true

        // Dragging anywhere moves it — a borderless window has no title bar to grab.
        isMovableByWindowBackground = true

        // No click-through: while the overlay is visible, clicks go to it and not to
        // whatever lies beneath.
        ignoresMouseEvents = false
    }

    /// Called when the user wants the overlay gone.
    var onCloseRequest: (() -> Void)?

    /// Escape hides the overlay. Without it there would be no way other than the
    /// button: a borderless, non-activating window has no close box, and ⌘W goes to
    /// whichever app is in front — not to AnyPlay.
    override func cancelOperation(_ sender: Any?) {
        onCloseRequest?()
    }

    /// A borderless window cannot become key otherwise, and then it receives no mouse
    /// events. The app is not activated by this — .nonactivatingPanel takes care of that.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
