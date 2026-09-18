// ScreenGeometry.swift — the two coordinate systems AnyPlay has to bridge.
//
// AppKit measures from the bottom left of the main display, upwards. The window
// server and the Accessibility API measure from the top left, downwards. The
// overlay is an NSWindow; the target window is moved through the Accessibility API.

import CoreGraphics

public enum ScreenGeometry {

    /// Converts in either direction; the flip is its own inverse.
    ///
    /// `referenceHeight` must be the height of the display that holds the origin of
    /// the global coordinate space — the one with the menu bar, `NSScreen.screens[0]`.
    /// It is NOT the display the rectangle happens to be on; that is what keeps the
    /// conversion correct across several monitors.
    public static func flip(_ rect: CGRect, referenceHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x,
               y: referenceHeight - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }

    public struct Display: Sendable {
        public var frame: CGRect
        public var backingScale: CGFloat
        public init(frame: CGRect, backingScale: CGFloat) {
            self.frame = frame
            self.backingScale = backingScale
        }
    }

    /// Pixels per point for a rectangle: that of the display it mostly overlaps.
    ///
    /// Needed when a window moves to another monitor. A Retina panel has 2, a typical
    /// external monitor 1 — keeping the old factor would stream at half or double
    /// the sensible resolution. Rectangle and display frames must share one
    /// coordinate system.
    public static func backingScale(for rect: CGRect, displays: [Display], fallback: CGFloat) -> CGFloat {
        var best: (area: CGFloat, scale: CGFloat)?
        for display in displays {
            let overlap = display.frame.intersection(rect)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if best == nil || area > best!.area { best = (area, display.backingScale) }
        }
        return best?.scale ?? fallback
    }
}
