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

    /// The system's Picture-in-Picture window, the one AnyPlay wants most.
    ///
    /// It is the best possible source: it contains nothing but the video — no address
    /// bar, no page header — and macOS shows it on every Space, so it keeps being
    /// drawn. A browser window on another Space does not: measured, ScreenCaptureKit
    /// then delivers zero frames and the mirror freezes.
    ///
    /// It has to be let through explicitly because it does not live on the normal
    /// window layer. Measured: layer 19, 493 × 258, owner "Bild-in-Bild".
    public static let pictureInPictureBundleID = "com.apple.PIPAgent"

    /// Picture-in-Picture can be dragged smaller than a real window ever gets, and a
    /// wide video is flat. Judged by the smaller side, a 16:9 picture 250 points wide
    /// is only 140 high — still a perfectly good source.
    public static let minimumSideForPictureInPicture: CGFloat = 120

    public static func isPictureInPicture(_ window: WindowCandidate) -> Bool {
        window.bundleID == pictureInPictureBundleID
    }

    public static func isUsable(_ window: WindowCandidate, ownBundleID: String?) -> Bool {
        let isPiP = isPictureInPicture(window)
        let smallestSide = isPiP ? minimumSideForPictureInPicture : minimumSide
        guard window.layer == 0 || isPiP,
              window.frame.width >= smallestSide, window.frame.height >= smallestSide,
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
