// OverlayChromeView.swift — the mirrored picture plus the overlay's few controls.
//
// The overlay is borderless and takes no focus, so neither a close box nor ⌘W works —
// without a button of its own you would be stuck. The button appears on hover and,
// in addition, for a few seconds after the overlay is shown, so it can be found at all.

import AppKit

final class OverlayChromeView: NSView {

    let mirror = MirrorView()
    var onClose: (() -> Void)?
    /// A control the viewer pressed in the overlay. The overlay itself knows nothing
    /// about how the command reaches the video.
    var onCommand: ((RemoteCommand) -> Void)?

    private let closeButton = NSButton()
    private let controlBar = NSStackView()
    private var backToBrowserButton: NSButton?
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

        buildControlBar()

        NSLayoutConstraint.activate([
            controlBar.centerXAnchor.constraint(equalTo: centerXAnchor),
            controlBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
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

    /// The transport controls. They are worth having because the Accessibility API
    /// can operate the system Picture-in-Picture window from behind a fullscreen
    /// game — a forwarded click cannot, which is measured and written down in
    /// PictureInPictureControls.
    private func buildControlBar() {
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.orientation = .horizontal
        controlBar.spacing = Self.controlSpacing
        controlBar.alphaValue = 0
        addSubview(controlBar)

        let buttons: [(RemoteCommand, String, String)] = [
            (.back10, "gobackward.10", "overlay.back10"),
            (.playPause, "playpause.fill", "action.playPause"),
            (.forward10, "goforward.10", "overlay.forward10"),
        ]
        for (command, symbol, key) in buttons {
            controlBar.addArrangedSubview(controlButton(command, symbol: symbol, key: key))
        }

        // Only useful for a Picture-in-Picture source, so it stays hidden otherwise.
        let back = controlButton(.backToBrowser, symbol: "arrow.uturn.backward",
                                 key: "overlay.backToBrowser")
        back.isHidden = true
        backToBrowserButton = back
        controlBar.addArrangedSubview(back)
    }

    /// Shows the way back into the browser. It is the answer to an advert: the button
    /// that skips it belongs to the web page, not to the video, so it is not in the
    /// mirrored picture and cannot be pressed from here. One press gets you to the
    /// page instead of hunting for the window.
    func setShowsBackToBrowser(_ shows: Bool) {
        backToBrowserButton?.isHidden = !shows
    }

    private func controlButton(_ command: RemoteCommand, symbol: String, key: String) -> NSButton {
        let title = L10n.tr(key)
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.wantsLayer = true
        // The same dark disc as the close button: readable on top of any picture,
        // and the symbol carries the meaning, not the colour.
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        button.layer?.cornerRadius = Self.controlSide / 2
        button.contentTintColor = .white
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        if button.image == nil { button.title = title }
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = title
        button.target = self
        button.action = #selector(controlTapped(_:))
        button.tag = RemoteCommand.allCases.firstIndex(of: command) ?? 0
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.controlSide),
            button.heightAnchor.constraint(equalToConstant: Self.controlSide),
        ])
        return button
    }

    /// 44 points: the same target size the window list uses, and large enough to hit
    /// without aiming on a small overlay.
    private static let controlSide: CGFloat = 44
    private static let controlSpacing: CGFloat = 12

    @objc private func controlTapped(_ sender: NSButton) {
        let commands = RemoteCommand.allCases
        guard commands.indices.contains(sender.tag) else { return }
        onCommand?(commands[sender.tag])
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
            controlBar.animator().alphaValue = visible ? 1 : 0
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
