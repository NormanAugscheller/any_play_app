// WindowPlacer.swift — puts the real target window beneath the overlay and back.
//
// Two lessons are built in:
//
// 1. One pass is not enough. macOS limits a window's height to the visible area
//    BELOW its current position. A small window at the bottom right cannot be made
//    large again in one step — it has to move up first, then grow. Two passes of
//    position and size handle both directions. Measured: without this, a 1300 × 727
//    window came back as 1300 × 322, although both set calls reported success.
//
// 2. The API's return value cannot be trusted. After every change the frame is read
//    back and compared. Safari, for example, has a minimum width of 574 points and
//    silently rounds a smaller request up.

import AppKit
import ApplicationServices
import AnyPlayKit

@MainActor
final class WindowPlacer {

    private(set) var state: PlacementState = .detached
    private var axWindow: AXUIElement?
    private var originalFrame: CGRect?
    private var target: TargetWindow?

    /// The original frame goes to disk as soon as a window is pinned, so a crash
    /// cannot lose it (see PlacementJournal and CrashRecovery).
    private let journal: PlacementJournal
    private let journalKey: String

    init(journal: PlacementJournal, journalKey: String) {
        self.journal = journal
        self.journalKey = journalKey
    }

    // MARK: Matching

    /// Finds the AX window for a known window. The Accessibility API knows no
    /// CGWindowID, so geometry decides first and the title only second. The other way
    /// round picks the wrong one when two windows share a title — two Finder windows of
    /// the same folder do, and during testing exactly that closed the wrong window.
    @discardableResult
    func attach(to target: TargetWindow) -> Bool {
        self.target = target
        let windows = AXBridge.windows(ofPID: target.processID)

        if let byFrame = windows.first(where: { window in
            guard let frame = AXBridge.frame(window) else { return false }
            return abs(frame.origin.x - target.frame.origin.x) < 3
                && abs(frame.origin.y - target.frame.origin.y) < 3
                && abs(frame.width - target.frame.width) < 3
                && abs(frame.height - target.frame.height) < 3
        }) {
            axWindow = byFrame
            return true
        }
        // Title as a fallback, in case the geometry changed between listing and access.
        if !target.title.isEmpty,
           let byTitle = windows.first(where: {
               AXBridge.string($0, kAXTitleAttribute as String) == target.title
           }) {
            axWindow = byTitle
            return true
        }
        axWindow = nil
        return false
    }

    // MARK: Pin and release

    /// Moves the window to `requested` (window-server coordinates) and reports what
    /// actually happened.
    @discardableResult
    func place(at requested: CGRect) -> CGRect? {
        guard AXBridge.isTrusted(prompt: false) else {
            state = .failed(L10n.tr("placement.error.noAccessibility"))
            return nil
        }
        guard let window = axWindow else {
            state = .failed(L10n.tr("placement.error.unreachable"))
            return nil
        }
        if originalFrame == nil { originalFrame = AXBridge.frame(window) }

        guard let actual = apply(requested, to: window) else {
            state = .failed(L10n.tr("placement.error.unreadable"))
            return nil
        }
        state = .placed(actual: actual, requested: requested)
        writeJournal(pinnedFrame: actual)
        return actual
    }

    /// Restores the state from before pinning.
    @discardableResult
    func restore() -> Bool {
        defer {
            state = .detached
            journal.remove(journalKey)
        }
        guard let window = axWindow, let original = originalFrame else { return false }
        originalFrame = nil
        guard let actual = apply(original, to: window) else { return false }
        // One point of tolerance: windows occasionally snap to whole pixels.
        return abs(actual.origin.x - original.origin.x) < 1
            && abs(actual.origin.y - original.origin.y) < 1
            && abs(actual.width - original.width) < 1
            && abs(actual.height - original.height) < 1
    }

    /// Records why attaching failed, so the interface can say something useful.
    ///
    /// The Accessibility API only lists windows on the CURRENT Space. A target in
    /// another Space — behind a fullscreen app, for example — is invisible to it. That
    /// is a limit of the API, not an error, and the fix is one click for the user.
    func markUnreachable(targetIsOnScreen: Bool) {
        state = .failed(targetIsOnScreen
                        ? L10n.tr("placement.error.unreachable")
                        : L10n.tr("placement.error.otherSpace"))
    }

    /// Asks the window server whether a window is on the current Space right now.
    static func isOnScreen(_ windowID: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = list.first else { return false }
        return (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
    }

    /// Forgets a window that no longer exists. There is nothing to put back, so the
    /// journal entry goes too — otherwise the next launch would look for a ghost.
    func forget() {
        journal.remove(journalKey)
        detach()
    }

    func detach() {
        axWindow = nil
        originalFrame = nil
        target = nil
        state = .detached
    }

    /// Raises the target window within its app. Needed for input mode: activating the
    /// app is not enough when another of its windows is on top.
    @discardableResult
    func raise() -> Bool {
        guard let window = axWindow else { return false }
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    // MARK: Minimizing

    var isMinimized: Bool {
        guard let window = axWindow else { return false }
        return AXBridge.bool(window, kAXMinimizedAttribute as String) ?? false
    }

    @discardableResult
    func unminimize() -> Bool {
        guard let window = axWindow else { return false }
        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                            kCFBooleanFalse) == .success
    }

    // MARK: Core

    /// Sets position and size in two passes and reads the result back.
    private func apply(_ rect: CGRect, to window: AXUIElement) -> CGRect? {
        for _ in 0..<2 {
            AXBridge.set(window, kAXPositionAttribute as String, point: rect.origin)
            AXBridge.set(window, kAXSizeAttribute as String, size: rect.size)
        }
        return AXBridge.frame(window)
    }

    private func writeJournal(pinnedFrame: CGRect) {
        guard let target, let originalFrame else { return }
        journal.set(PlacementRecord(processID: target.processID,
                                    bundleID: target.bundleID,
                                    windowTitle: target.title,
                                    originalFrame: originalFrame,
                                    pinnedFrame: pinnedFrame),
                    for: journalKey)
    }
}
