// OverlayController.swift — building and tearing down the overlay for one target.

import AppKit

@MainActor
final class OverlayController {

    private(set) var panel: OverlayPanel?
    private let chrome = OverlayChromeView()
    private var mirror: MirrorView { chrome.mirror }

    /// The user wants the overlay hidden — via the button or Escape.
    var onCloseRequest: (() -> Void)?
    /// Every move and resize. The target window has to follow, or it no longer lies
    /// beneath the overlay.
    var onFrameChanged: (() -> Void)?

    private var frameObservers: [NSObjectProtocol] = []
    private var surfaceToken: UUID?
    /// How many frames the overlay has received. Only for measurement: whether the
    /// overlay is still drawn cannot be told from the picture while the source is still.
    private(set) var drawCount = 0
    private let capture: CaptureSession

    /// Initial width in points. The height follows the source's aspect ratio.
    private static let defaultWidth: CGFloat = 480
    private static let margin: CGFloat = 24

    init(capture: CaptureSession) {
        self.capture = capture
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(sourceSize: CGSize) {
        if panel == nil { build(sourceSize: sourceSize) }
        guard let panel else { return }
        // orderFrontRegardless instead of makeKeyAndOrderFront: the panel should
        // appear without bringing AnyPlay to the front.
        panel.orderFrontRegardless()
        chrome.revealControls(for: 6)
        if surfaceToken == nil {
            surfaceToken = capture.addSurfaceHandler { [weak self] surface in
                guard let self else { return }
                self.drawCount += 1
                self.mirror.show(surface)
            }
        }
    }

    func showMessage(_ text: String, actionTitle: String?, action: (() -> Void)?) {
        chrome.showMessage(text, actionTitle: actionTitle, action: action)
    }

    func clearMessage() {
        chrome.clearMessage()
    }

    func hide() {
        panel?.orderOut(nil)
        if let token = surfaceToken {
            capture.removeSurfaceHandler(token)
            surfaceToken = nil
        }
        mirror.clear()
    }

    func close() {
        hide()
        panel?.close()
        panel = nil
    }

    /// Adapts the aspect ratio to a new source without closing the overlay.
    func updateAspect(sourceSize: CGSize) {
        guard let panel, sourceSize.width > 0, sourceSize.height > 0 else { return }
        panel.contentAspectRatio = sourceSize
        let width = panel.frame.width
        let height = width * sourceSize.height / sourceSize.width
        panel.setContentSize(NSSize(width: width, height: height))
    }

    /// Adapts the panel and its limits to what the target app actually allowed.
    /// Without this, the real window would not line up with the overlay — and lining
    /// up is the whole point.
    func adoptActualFrame(_ frame: NSRect) {
        guard let panel else { return }
        panel.contentAspectRatio = frame.size
        panel.contentMinSize = frame.size
        panel.setFrame(frame, display: true)
    }

    private func observeFrameChanges(of panel: NSPanel) {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let token = center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onFrameChanged?() }
            }
            frameObservers.append(token)
        }
    }

    deinit {
        frameObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func build(sourceSize: CGSize) {
        let aspect = (sourceSize.width > 0 && sourceSize.height > 0)
            ? sourceSize.height / sourceSize.width
            : 9.0 / 16.0
        let width = Self.defaultWidth
        let height = (width * aspect).rounded()

        // visibleFrame rather than frame: it excludes the menu bar and the Dock, so the
        // panel does not start underneath the Dock or behind the notch.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1470, height: 900)
        let origin = NSPoint(x: screen.maxX - width - Self.margin,
                             y: screen.minY + Self.margin)
        let panel = OverlayPanel(contentRect: NSRect(origin: origin,
                                                     size: NSSize(width: width, height: height)))
        panel.contentAspectRatio = NSSize(width: sourceSize.width, height: sourceSize.height)
        panel.contentMinSize = NSSize(width: 200, height: 120)
        panel.contentView = chrome
        chrome.onClose = { [weak self] in self?.onCloseRequest?() }
        panel.onCloseRequest = { [weak self] in self?.onCloseRequest?() }
        panel.setFrameAutosaveName("AnyPlayOverlay")
        self.panel = panel
        observeFrameChanges(of: panel)
    }
}
