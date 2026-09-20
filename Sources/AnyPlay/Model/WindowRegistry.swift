// WindowRegistry.swift — which foreign windows exist right now.

import AppKit
import ScreenCaptureKit
import AnyPlayKit

@MainActor
final class WindowRegistry: ObservableObject {

    /// The states every loading screen needs. `ready([])` is the empty state — the
    /// one a new user sees first.
    enum State {
        case loading
        case ready([TargetWindow])
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    /// Every window ID the window server knows right now.
    private static func liveWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return Set(list.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    }

    /// True once a list has been delivered at least once.
    private var hasList: Bool {
        if case .ready = state { return true }
        return false
    }

    /// - Parameter showingLoadingState: pass `false` for an automatic refresh. The
    ///   current list then stays on screen until the new one arrives. Blinking back to
    ///   "Looking for windows" every time the window is focused would look broken.
    func refresh(showingLoadingState: Bool = true) async {
        if showingLoadingState || !hasList { state = .loading }
        do {
            // onScreenWindowsOnly: false — a window in another Space must stay listed,
            // or the target would vanish as soon as a game goes fullscreen.
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            // ScreenCaptureKit keeps listing closed windows for minutes. Measured: a
            // window closed through Accessibility was still listed half a minute later.
            // The window server knows immediately, so the list is checked against it.
            let live = Self.liveWindowIDs()
            let own = Bundle.main.bundleIdentifier
            let windows = content.windows
                .filter { live.contains($0.windowID) }
                .filter { WindowFilter.isUsable(WindowCandidate($0), ownBundleID: own) }
                .compactMap(TargetWindow.init)
                .sorted { lhs, rhs in
                    if lhs.appName == rhs.appName { return lhs.displayTitle < rhs.displayTitle }
                    return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
                }
            state = .ready(windows)
            DiagnosticLog.shared?.line("LIST \(windows.count) windows: "
                + Set(windows.map(\.appName)).sorted().joined(separator: ", "))
        } catch {
            state = .failed(Self.explain(error))
        }
    }

    /// Turns a bare error code into something that can be shown in the window.
    private static func explain(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == -3801 {
            return L10n.tr("error.screenRecordingDenied.long")
        }
        return nsError.localizedDescription
    }
}
