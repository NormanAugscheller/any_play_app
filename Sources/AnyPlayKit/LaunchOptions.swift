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
