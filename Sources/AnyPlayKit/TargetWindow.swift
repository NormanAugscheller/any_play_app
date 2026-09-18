// TargetWindow.swift — a foreign window as AnyPlay knows it.

import CoreGraphics

/// Window IDs become invalid as soon as an app rebuilds its window. A window is
/// therefore found again by process and title, never by its ID.
public struct WindowIdentity: Hashable, Sendable {
    public let processID: pid_t
    public let title: String

    public init(processID: pid_t, title: String) {
        self.processID = processID
        self.title = title
    }
}

public struct TargetWindow: Identifiable, Hashable, Sendable {
    public let windowID: CGWindowID
    public let processID: pid_t
    public let bundleID: String?
    public let appName: String
    public let title: String
    /// In window-server coordinates: origin at the top left of the main display.
    public let frame: CGRect
    public let isOnScreen: Bool

    public init(windowID: CGWindowID, processID: pid_t, bundleID: String?, appName: String,
                title: String, frame: CGRect, isOnScreen: Bool) {
        self.windowID = windowID
        self.processID = processID
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
    }

    public var id: CGWindowID { windowID }
    public var identity: WindowIdentity { WindowIdentity(processID: processID, title: title) }

    /// Language-neutral size, e.g. "1300 × 727".
    public var sizeDescription: String {
        "\(Int(frame.width)) × \(Int(frame.height))"
    }
}
