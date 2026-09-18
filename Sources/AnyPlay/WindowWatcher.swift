// WindowWatcher.swift — makes sure the target window does not quietly disappear.
//
// Three cases that happen in practice:
//
// 1. Minimized. Another app cannot be stopped from doing that. Noticing and undoing
//    it works — otherwise the overlay would show a frozen picture.
// 2. Window ID invalid. It changes when an app rebuilds its window. The window is
//    found again by process AND title (see Rediscovery).
// 3. Window closed. Then a placeholder appears — and explicitly NOT the window
//    behind it, or your mail might suddenly sit on top of your game.

import AppKit
import AnyPlayKit

@MainActor
final class WindowWatcher {

    enum Finding {
        case fine
        case wasMinimized           // noticed and undone
        case rediscovered(TargetWindow)
        case gone
    }

    private var timer: Timer?
    private let registry: WindowRegistry
    private var isChecking = false

    var onFinding: ((Finding) -> Void)?

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    func start(checking session: PinSession) {
        stop()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self, weak session] _ in
            guard let self, let session else { return }
            Task { @MainActor in await self.check(session) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DiagnosticLog.shared?.line("WATCHER started for \(session.target?.title ?? "-")")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Asks the window server directly. A closed window yields an empty list — the
    /// cheapest and most reliable existence check there is.
    private static func windowExists(_ id: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]]
        else { return false }
        return !list.isEmpty
    }

    private func check(_ session: PinSession) async {
        guard !isChecking, let target = session.target else { return }
        isChecking = true
        defer { isChecking = false }

        if session.restoreFromMinimized() {
            onFinding?(.wasMinimized)
            return
        }

        // Cheap check first. Asking ScreenCaptureKit for the full list every 1.5
        // seconds was expensive and stale: a closed window stayed in its list for
        // minutes, and the watcher never noticed.
        if Self.windowExists(target.windowID) {
            onFinding?(.fine)
            return
        }
        DiagnosticLog.shared?.line("WATCHER window \(target.windowID) no longer exists")

        // Only now the expensive search.
        await registry.refresh()
        guard case .ready(let windows) = registry.state else {
            DiagnosticLog.shared?.line("WATCHER window list unavailable")
            return
        }
        if let again = Rediscovery.find(target, in: windows) {
            onFinding?(.rediscovered(again))
        } else {
            onFinding?(.gone)
        }
    }
}
