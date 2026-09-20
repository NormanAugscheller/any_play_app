// LaunchOptions.swift — command-line switches for development and testing.
//
// They exist because the app can otherwise only be driven by hand, and an automated
// test cannot use the mouse. None of them is needed in normal use.
//
//   --select com.apple.Safari     pick the largest window of that app
//   --select-title "YouTube"      narrow it down by title
//   --overlay                     show the overlay right away
//   --no-pin                      mirror only, never move the real window
//   --log /path/file.log          write the state once per second
//   --quit-after 30               quit after 30 seconds
//   --selftest-input              switch into input mode and back
//   --open-settings               open the settings window on launch
//   --selftest-playpause          send one play/pause five seconds after launch
//   --dump-frame /path/f.png      write one captured frame as a PNG
//   --selftest-click              click the middle of the source window once
//   --selftest-ax-find id=text    search that app's Accessibility tree for "text"

import Foundation

public struct LaunchOptions: Equatable, Sendable {
    public var selectBundleID: String?
    public var selectTitleContains: String?
    public var showOverlayImmediately = false
    public var placesTargetWindow = true
    public var logPath: String?
    public var quitAfter: TimeInterval?
    public var runsInputSelftest = false
    public var opensSettings = false
    /// Test switch: sends one play/pause a few seconds after launch. The media key
    /// can only be posted by a process that macOS trusts for input, so it cannot be
    /// tried from a loose script — it has to come from AnyPlay itself.
    public var sendsPlayPauseOnLaunch = false
    /// Test switch: writes one captured frame to this path as a PNG.
    public var dumpFramePath: String?
    /// Test switch: clicks the middle of the source window, to find out whether a
    /// forwarded click reaches it at all.
    public var clicksSourceCentreOnLaunch = false
    /// Test switch: "<bundleID>=<text>" searches that app's Accessibility tree.
    public var accessibilitySearch: String?

    public static let current = LaunchOptions(CommandLine.arguments)

    public init(_ arguments: [String]) {
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            let value = (index + 1 < arguments.count) ? arguments[index + 1] : ""
            switch key {
            case "--select":         selectBundleID = value.isEmpty ? nil : value; index += 2
            case "--select-title":   selectTitleContains = value.isEmpty ? nil : value; index += 2
            case "--overlay":        showOverlayImmediately = true; index += 1
            case "--no-pin":         placesTargetWindow = false; index += 1
            case "--log":            logPath = value.isEmpty ? nil : value; index += 2
            case "--quit-after":     quitAfter = Double(value); index += 2
            case "--selftest-input": runsInputSelftest = true; index += 1
            case "--open-settings":  opensSettings = true; index += 1
            case "--selftest-playpause": sendsPlayPauseOnLaunch = true; index += 1
            case "--dump-frame":     dumpFramePath = value.isEmpty ? nil : value; index += 2
            case "--selftest-click": clicksSourceCentreOnLaunch = true; index += 1
            case "--selftest-ax-find": accessibilitySearch = value.isEmpty ? nil : value; index += 2
            default:                 index += 1
            }
        }
    }

    public var hasAutoSelection: Bool { selectBundleID != nil }

    /// The largest matching window is the most likely target.
    public func match(in windows: [TargetWindow]) -> TargetWindow? {
        guard let bundleID = selectBundleID else { return nil }
        var candidates = windows.filter { $0.bundleID == bundleID }
        if let needle = selectTitleContains {
            candidates = candidates.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        }
        return candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}
