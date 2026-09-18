// WindowFilter.swift — which windows are worth offering as a target.

import CoreGraphics

/// The facts about a window that decide whether it is a sensible target. Kept free
/// of ScreenCaptureKit types so the rules can be tested without a window server.
public struct WindowCandidate: Sendable {
    public var layer: Int
    public var frame: CGRect
    public var title: String?
    public var isOnScreen: Bool
    public var bundleID: String?
    public var hasOwningApplication: Bool

    public init(layer: Int, frame: CGRect, title: String?, isOnScreen: Bool,
                bundleID: String?, hasOwningApplication: Bool = true) {
        self.layer = layer
        self.frame = frame
        self.title = title
        self.isOnScreen = isOnScreen
        self.bundleID = bundleID
        self.hasOwningApplication = hasOwningApplication
    }
}

public enum WindowFilter {

    /// Anything smaller is a toolbar strip, a leftover or a helper window. Measured:
    /// Safari keeps six untitled windows on layer 0, one of them 500 × 500.
    public static let minimumSide: CGFloat = 200

    public static func isUsable(_ window: WindowCandidate, ownBundleID: String?) -> Bool {
        guard window.layer == 0,
              window.frame.width >= minimumSide, window.frame.height >= minimumSide,
              window.hasOwningApplication
        else { return false }
        if let own = ownBundleID, window.bundleID == own { return false }
        // Untitled windows that are not on screen are almost always clutter: menu bar
        // apps keep closed windows around, Safari keeps several untitled leftovers.
        // An untitled window you can actually see stays, and so does a titled window in
        // another Space — that is exactly where the target lives while a game runs.
        if (window.title ?? "").isEmpty && !window.isOnScreen { return false }
        return true
    }
}
