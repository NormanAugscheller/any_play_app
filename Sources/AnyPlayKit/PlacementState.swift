// PlacementState.swift — where the real window is relative to the overlay.

import CoreGraphics

public enum PlacementState: Equatable, Sendable {
    case detached
    /// The window lies beneath the overlay. `actual` is what the app allowed.
    case placed(actual: CGRect, requested: CGRect)
    case failed(String)

    public var isPlaced: Bool {
        if case .placed = self { return true }
        return false
    }

    /// Does the result differ from the request? Then the real window does not line up
    /// with the overlay, and a click in input mode would land somewhere else.
    /// Safari, for example, refuses to get narrower than 574 points.
    public var mismatch: CGSize? {
        guard case .placed(let actual, let requested) = self else { return nil }
        let dw = actual.width - requested.width
        let dh = actual.height - requested.height
        return (abs(dw) < 1 && abs(dh) < 1) ? nil : CGSize(width: dw, height: dh)
    }
}
