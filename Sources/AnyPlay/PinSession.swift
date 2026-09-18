// PinSession.swift — one pinned window: source, stream and overlay.
//
// Everything that belongs to ONE pin lives here. PinManager holds a list of them.
// The app uses exactly one entry; several overlays at once would mean adding to the
// list, not rebuilding.

import AppKit
import AnyPlayKit

/// Two ways of working. Moving the mouse into a background window turned out to be
/// impossible (see InputForwarder), which decided how the work is split.
enum PinMode {
    /// The game keeps focus. The overlay only shows; control goes through commands
    /// that are delivered to the target process as key presses.
    case passive
    /// The target app is really activated. Its real window lies pixel-exactly beneath
    /// the overlay, so typing and clicking work normally.
    case input
}

@MainActor
final class PinSession: Identifiable {
    let id = UUID()
    let capture = CaptureSession()
    private(set) lazy var overlay = OverlayController(capture: capture)
    private(set) var target: TargetWindow?
    private lazy var placer = WindowPlacer(journal: .standard, journalKey: id.uuidString)
    /// Keeps adjusting the panel from triggering another adjustment right away.
    private var isSyncing = false

    /// Called whenever placement or mode change.
    var onPlacementChanged: (() -> Void)?
    private(set) var mode: PinMode = .passive
    /// Where focus returns when leaving input mode — in practice, the game. Stored as
    /// a process ID because it is later activated through the Accessibility API.
    private var pidBeforeInputMode: pid_t?
    var placement: PlacementState { placer.state }

    func start(window: TargetWindow) async {
        target = window
        // Attach before pinning, so a minimized window can be noticed even while the
        // overlay only mirrors.
        placer.attach(to: window)
        await capture.start(window: window)
        if overlay.isVisible {
            overlay.updateAspect(sourceSize: window.frame.size)
        }
    }

    func showOverlay() {
        guard let target else { return }
        overlay.onFrameChanged = { [weak self] in self?.syncTargetToOverlay() }
        overlay.show(sourceSize: target.frame.size)
        pinTargetWindow()
    }

    func hideOverlay() {
        unpinTargetWindow()
        overlay.hide()
    }

    func toggleOverlay() {
        overlay.isVisible ? hideOverlay() : showOverlay()
    }

    // MARK: Pinning

    /// Places the real window beneath the overlay. Without the Accessibility
    /// permission the overlay stays a mirror — that is a reduced mode, not an error,
    /// and it is shown as such.
    func pinTargetWindow() {
        // --no-pin on the command line wins; otherwise the setting decides.
        guard LaunchOptions.current.placesTargetWindow, Settings.placesTargetWindow else {
            DiagnosticLog.shared?.line("PIN skipped: placing is turned off")
            return
        }
        guard let target else { return }
        guard placer.attach(to: target) else {
            let onScreen = WindowPlacer.isOnScreen(target.windowID)
            placer.markUnreachable(targetIsOnScreen: onScreen)
            DiagnosticLog.shared?.line("PIN failed: no Accessibility window matches \(target.frame), "
                                     + "onScreen=\(onScreen)")
            onPlacementChanged?()
            return
        }
        syncTargetToOverlay()
    }

    func unpinTargetWindow() {
        guard placer.state.isPlaced else { return }
        _ = placer.restore()
        placer.detach()
        if let target {
            placer.attach(to: target)
            // The source is back at its old size — the stream has to follow.
            let frame = target.frame
            Task { await capture.updateSource(frame: frame) }
        }
        onPlacementChanged?()
    }

    /// Moves the target window to wherever the overlay is right now.
    func syncTargetToOverlay() {
        guard !isSyncing, let panel = overlay.panel else { return }
        isSyncing = true
        defer { isSyncing = false }

        let requested = ScreenCoordinates.windowServerRect(fromAppKit: panel.frame)
        guard let actual = placer.place(at: requested) else {
            DiagnosticLog.shared?.line("PIN failed: \(placer.state)")
            onPlacementChanged?()
            return
        }
        DiagnosticLog.shared?.line("PIN requested \(requested) → actual \(actual)")
        if actual.size != requested.size {
            // The app enforced a minimum size. Instead of lying next to it, the overlay
            // follows what is possible — and can no longer be dragged smaller than the
            // source allows.
            overlay.adoptActualFrame(ScreenCoordinates.appKitRect(fromWindowServer: actual))
            // Place once more so the reported state matches what is true now: panel
            // and window line up again. Otherwise the mismatch from a moment ago
            // would stay on screen although it has been resolved.
            _ = placer.place(at: ScreenCoordinates.windowServerRect(fromAppKit: panel.frame))
        }
        // The source is now smaller than when the stream started; without adjusting
        // the resolution the picture arrives letterboxed in black.
        Task { await capture.updateSource(frame: actual) }
        onPlacementChanged?()
    }

    /// Takes over a window that was found again after the old one vanished. The old
    /// one is gone, so there is nothing to restore; the new one goes beneath the
    /// overlay if the overlay is showing.
    func adopt(_ window: TargetWindow) async {
        placer.forget()
        await start(window: window)
        if overlay.isVisible { pinTargetWindow() }
    }

    /// The target window is gone for good.
    func targetVanished() {
        placer.forget()
        onPlacementChanged?()
    }

    /// Nobody can stop another app from being minimized. Noticing and undoing it works.
    @discardableResult
    func restoreFromMinimized() -> Bool {
        guard placer.isMinimized else { return false }
        let ok = placer.unminimize()
        DiagnosticLog.shared?.line("Target window was minimized, restored: \(ok)")
        return ok
    }

    // MARK: Modes

    /// Activates the target app and raises its window. Because the window lies exactly
    /// beneath the overlay, the switch looks like a switch within the same picture.
    func enterInputMode() {
        guard mode == .passive, let target else { return }
        pidBeforeInputMode = NSWorkspace.shared.frontmostApplication?.processIdentifier
        placer.raise()
        AXBridge.bringToFront(pid: target.processID)
        mode = .input
        onPlacementChanged?()
    }

    /// Gives focus back to wherever it was before.
    func leaveInputMode() {
        guard mode == .input else { return }
        if let pid = pidBeforeInputMode { AXBridge.bringToFront(pid: pid) }
        pidBeforeInputMode = nil
        mode = .passive
        onPlacementChanged?()
    }

    func toggleMode() {
        mode == .passive ? enterInputMode() : leaveInputMode()
    }

    /// Sends a command to the target window without touching focus.
    @discardableResult
    func send(_ command: RemoteCommand) -> Bool {
        guard let target else { return false }
        let ok = InputForwarder.send(command, to: target.processID)
        DiagnosticLog.shared?.line("Command \(command.logName) to pid \(target.processID): \(ok)")
        return ok
    }

    func stop() async {
        leaveInputMode()
        unpinTargetWindow()
        overlay.close()
        await capture.stop()
        target = nil
    }
}

@MainActor
final class PinManager: ObservableObject {
    @Published private(set) var sessions: [PinSession] = []

    /// The app works with exactly one session.
    var primary: PinSession {
        if let existing = sessions.first { return existing }
        let session = PinSession()
        sessions.append(session)
        return session
    }
}
