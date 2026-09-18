// OverlayChromeView.swift — the mirrored picture plus the overlay's few controls.
//
// The overlay is borderless and takes no focus, so neither a close box nor ⌘W works —
// without a button of its own you would be stuck. The button appears on hover and,
// in addition, for a few seconds after the overlay is shown, so it can be found at all.

import AppKit

final class OverlayChromeView: NSView {

    let mirror = MirrorView()
    var onClose: (() -> Void)?

    private let closeButton = NSButton()
    private let messageLabel = NSTextField(labelWithString: "")
    private let messageButton = NSButton(title: "", target: nil, action: nil)
    private var messageAction: (() -> Void)?
    private var hideTimer: Timer?
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        wantsLayer = true

        mirror.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mirror)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        // A dark disc with a white mark: readable on top of any picture. Colour alone
        // carries no information here.
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        closeButton.layer?.cornerRadius = 14
        closeButton.contentTintColor = .white
        closeButton.image = NSImage(systemSymbolName: "xmark",
                                    accessibilityDescription: L10n.tr("overlay.close.accessibility"))
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.toolTip = L10n.tr("overlay.close.tooltip")
        closeButton.alphaValue = 0
        addSubview(closeButton)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .center
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.maximumNumberOfLines = 3
        messageLabel.isHidden = true
        addSubview(messageLabel)

        messageButton.translatesAutoresizingMaskIntoConstraints = false
        messageButton.bezelStyle = .rounded
        messageButton.target = self
        messageButton.action = #selector(messageButtonTapped)
        messageButton.isHidden = true
        addSubview(messageButton)

        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            messageButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
            messageButton.centerXAnchor.constraint(equalTo: centerXAnchor),

            mirror.topAnchor.constraint(equalTo: topAnchor),
            mirror.leadingAnchor.constraint(equalTo: leadingAnchor),
            mirror.trailingAnchor.constraint(equalTo: trailingAnchor),
            mirror.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func messageButtonTapped() { messageAction?() }

    /// Shows a message instead of the picture. Used when the target window is gone:
    /// AnyPlay then explicitly does NOT take the window behind it, it asks.
    func showMessage(_ text: String, actionTitle: String?, action: (() -> Void)?) {
        mirror.clear()
        messageLabel.stringValue = text
        messageLabel.isHidden = false
        messageAction = action
        messageButton.title = actionTitle ?? ""
        messageButton.isHidden = (actionTitle == nil)
        revealControls(for: 6)
    }

    func clearMessage() {
        messageLabel.isHidden = true
        messageButton.isHidden = true
        messageAction = nil
    }

    // MARK: Showing and hiding the controls

    /// Shows the button and hides it again after a while.
    func revealControls(for seconds: TimeInterval = 4) {
        setControls(visible: true)
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            self?.setControls(visible: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func setControls(visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            // 200 ms: within the span that still feels immediate.
            context.duration = 0.2
            closeButton.animator().alphaValue = visible ? 1 : 0
        }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hideTimer?.invalidate()
        setControls(visible: true)
    }

    override func mouseExited(with event: NSEvent) {
        setControls(visible: false)
    }
}
