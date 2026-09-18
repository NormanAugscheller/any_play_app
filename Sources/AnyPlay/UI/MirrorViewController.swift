// MirrorViewController.swift — the right half: picture plus status line.

import AppKit
import Combine
import AnyPlayKit

@MainActor
final class MirrorViewController: NSViewController {

    private let capture: CaptureSession
    private let mirror = MirrorView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let placeholder = NSTextField(labelWithString: L10n.tr("mirror.placeholder.choose"))
    private let overlayButton = NSButton(title: L10n.tr("action.showOverlay"), target: nil, action: nil)
    private let playPauseButton = NSButton(title: L10n.tr("action.playPause"), target: nil, action: nil)
    private let modeButton = NSButton(title: L10n.tr("action.inputMode"), target: nil, action: nil)

    /// The window only reports the wish; it does not know what a pin is.
    var onToggleOverlay: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onToggleMode: (() -> Void)?

    /// What happened to the real window, appended to the status line.
    private var placementText: String?
    private var subscriptions = Set<AnyCancellable>()

    init(capture: CaptureSession) {
        self.capture = capture
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setPlacement(_ text: String?) {
        placementText = text
        updateStatus()
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        mirror.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        // The mirror is black. secondaryLabelColor would be dark grey on black in light
        // mode and unreadable — contrast has to be measured against the actual
        // background, not against the system theme.
        placeholder.textColor = NSColor.white.withAlphaComponent(0.75)
        placeholder.font = .systemFont(ofSize: 13)
        placeholder.alignment = .center

        root.addSubview(mirror)
        root.addSubview(placeholder)
        root.addSubview(statusLabel)
        for button in [playPauseButton, modeButton, overlayButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .rounded
            button.target = self
            button.isEnabled = false
            root.addSubview(button)
        }
        overlayButton.action = #selector(toggleOverlay)
        playPauseButton.action = #selector(playPauseTapped)
        modeButton.action = #selector(modeTapped)

        NSLayoutConstraint.activate([
            mirror.topAnchor.constraint(equalTo: root.topAnchor),
            mirror.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mirror.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mirror.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            placeholder.centerXAnchor.constraint(equalTo: mirror.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: mirror.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: playPauseButton.leadingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: overlayButton.centerYAnchor),

            overlayButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            overlayButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            overlayButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            modeButton.trailingAnchor.constraint(equalTo: overlayButton.leadingAnchor, constant: -8),
            modeButton.centerYAnchor.constraint(equalTo: overlayButton.centerYAnchor),
            playPauseButton.trailingAnchor.constraint(equalTo: modeButton.leadingAnchor, constant: -8),
            playPauseButton.centerYAnchor.constraint(equalTo: overlayButton.centerYAnchor),
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        capture.addSurfaceHandler { [weak self] surface in
            guard let self else { return }
            // The preview window is usually closed or in another Space while the
            // overlay runs over a game. Drawing every frame here anyway cost measurable
            // frame rate — so only draw when the window can actually be seen.
            guard let window = self.view.window, window.isVisible,
                  window.occlusionState.contains(.visible) else { return }
            self.mirror.show(surface)
            self.placeholder.isHidden = true
        }

        capture.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &subscriptions)

        capture.$framesPerSecond
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatus() }
            .store(in: &subscriptions)
    }

    @objc private func toggleOverlay() { onToggleOverlay?() }
    @objc private func playPauseTapped() { onPlayPause?() }
    @objc private func modeTapped() { onToggleMode?() }

    func setMode(_ mode: PinMode) {
        modeButton.title = mode == .passive ? L10n.tr("action.inputMode") : L10n.tr("action.backToGame")
    }

    func setOverlayVisible(_ visible: Bool) {
        overlayButton.title = visible ? L10n.tr("action.hideOverlay") : L10n.tr("action.showOverlay")
    }

    private func apply(_ state: CaptureSession.State) {
        let running = (state == .running)
        overlayButton.isEnabled = running
        playPauseButton.isEnabled = running
        modeButton.isEnabled = running
        switch state {
        case .idle:
            mirror.clear()
            placeholder.stringValue = L10n.tr("mirror.placeholder.choose")
            placeholder.isHidden = false
        case .starting:
            placeholder.stringValue = L10n.tr("mirror.placeholder.connecting")
            placeholder.isHidden = false
        case .running:
            break
        case .failed(let message):
            mirror.clear()
            placeholder.stringValue = message
            placeholder.isHidden = false
        }
        updateStatus()
    }

    private func updateStatus() {
        switch capture.state {
        case .idle:
            statusLabel.stringValue = L10n.tr("status.ready")
        case .starting:
            statusLabel.stringValue = L10n.tr("status.starting")
        case .failed(let message):
            statusLabel.stringValue = L10n.tr("status.error", message)
        case .running:
            let fps = capture.framesPerSecond
            var text = L10n.tr("status.fps", capture.window?.appName ?? "—", fps)
            let size = capture.pixelSize
            if size != .zero {
                text += " · \(Int(size.width))×\(Int(size.height)) px"
            }
            // Better to name a throttled source than to show a stuttering picture
            // without a word.
            switch FrameRateVerdict.classify(framesPerSecond: fps) {
            case .stalled:   text += "  " + L10n.tr("status.stalled")
            case .throttled: text += "  " + L10n.tr("status.throttled")
            case .idle, .healthy: break
            }
            if let placementText { text += "  ·  " + placementText }
            statusLabel.stringValue = text
        }
    }
}
