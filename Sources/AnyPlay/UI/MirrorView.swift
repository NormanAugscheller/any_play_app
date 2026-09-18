// MirrorView.swift — shows the mirrored picture.
//
// The IOSurface goes straight to CALayer.contents. That is the path without a copy:
// the GPU draws the very surface ScreenCaptureKit filled.

import AppKit
import IOSurface

final class MirrorView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // resizeAspect: better black bars than a distorted picture.
        layer?.contentsGravity = .resizeAspect
        // Without this, scaled-down text flickers visibly.
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
    }

    override var isFlipped: Bool { true }

    func show(_ surface: IOSurface) {
        // Without disabling actions, Core Animation animates every frame change and
        // the picture turns soft and sluggish.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = surface
        CATransaction.commit()
    }

    func clear() {
        layer?.contents = nil
    }
}
