// Rediscovery.swift — finding a pinned window again after its ID vanished.

/// The rule is deliberately strict: same process AND same, non-empty title.
///
/// An earlier version fell back to "any window of the same process". That broke the
/// most important promise of the app: when the pinned window is closed while another
/// window of the same app is open, AnyPlay silently switched to that other window —
/// your mail could suddenly sit on top of your game. A closed window now always
/// leads to a placeholder, never to the window behind it.
public enum Rediscovery {

    public static func find(_ target: TargetWindow, in windows: [TargetWindow]) -> TargetWindow? {
        guard !target.title.isEmpty else { return nil }
        return windows.first { candidate in
            candidate.identity == target.identity && candidate.windowID != target.windowID
        }
    }
}
