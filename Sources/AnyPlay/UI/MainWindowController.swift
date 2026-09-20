// MainWindowController.swift — the main window: window list on the left, preview on
// the right. The overlay itself is an NSPanel above everything; this window is where
// a target is chosen.

import AppKit
import SwiftUI
import Combine
import AnyPlayKit

@MainActor
final class MainWindowController: NSWindowController {

    private let registry = WindowRegistry()
    private let pins = PinManager()
    private let selection = Selection()
    private var mirrorController: MirrorViewController?
    private var diagnosticTimer: Timer?
    private lazy var watcher = WindowWatcher(registry: registry)
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var settingsObserver: NSObjectProtocol?
    private var windowKeyObserver: NSObjectProtocol?
    private var isShowingMainContent = false
    private var refreshTask: Task<Void, Never>?

    /// The app works with exactly one pin; the list behind it is ready for more.
    private var pin: PinSession { pins.primary }
    private var permissionTimer: Timer?
    private var grantedNeedsRestart = false
    private var hasSizedWindow = false
    private static let defaultSize = NSSize(width: 1000, height: 620)

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "AnyPlay"
        window.center()
        window.setFrameAutosaveName("AnyPlayMainWindow")
        super.init(window: window)
        showAppropriateContent()
        observeWindowFocus()
        startDiagnosticLogIfRequested()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// With --log, writes the state once per second. Without it there would be no way
    /// to check what the app does while a game runs fullscreen and nobody can see it.
    private func startDiagnosticLogIfRequested() {
        guard let log = DiagnosticLog.shared else { return }
        log.line("START AnyPlay screenRecording=\(Permission.screenRecording.isGranted) "
               + "accessibility=\(Permission.accessibility.isGranted) "
               + "policy=\(NSApp.activationPolicy() == .accessory ? "accessory" : "regular") "
               + "fps=\(Settings.maximumFPS) cursor=\(Settings.showsCursor) "
               + "place=\(Settings.placesTargetWindow) "
               + "language=\(Bundle.main.preferredLocalizations.first ?? "?")")
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let panel = self.pin.overlay.panel
                log.line("overlayDraws=\(self.pin.overlay.drawCount) "
                       + "ax=\(Permission.accessibility.isGranted) "
                       + "fps=\(self.pin.capture.framesPerSecond) "
                       + "changed=\(self.pin.capture.changedFramesPerSecond) "
                       + "state=\(self.pin.capture.state) "
                       + "overlay=\(self.pin.overlay.isVisible) "
                       + "level=\(panel?.level.rawValue ?? -1) "
                       + "alpha=\(panel?.alphaValue ?? -1) "
                       + "opaque=\(panel?.isOpaque ?? false) "
                       + "front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        diagnosticTimer = timer
    }

    // MARK: Keeping the window list current

    /// The list used to be fetched once, when the window was first built. Open an app
    /// afterwards and it was missing — with no hint that the "Reload" button had to be
    /// pressed. So every time the window comes to the front, the list is fetched again.
    private func observeWindowFocus() {
        windowKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshWindowList() }
            }
    }

    /// Fetching the list takes a moment and `bringWindowForward` also makes the window
    /// key, so the call can arrive twice. A running fetch swallows the second one.
    private func refreshWindowList() {
        guard isShowingMainContent, refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.registry.refresh(showingLoadingState: false)
            self?.refreshTask = nil
        }
    }

    // MARK: Content

    /// While Screen Recording is missing there is no window list — it would be an
    /// empty list without explanation.
    private func showAppropriateContent() {
        if Permission.screenRecording.isGranted {
            showMainContent()
        } else {
            showPermissionGate()
        }
    }

    private func showPermissionGate() {
        let view = PermissionGateView(
            permission: .screenRecording,
            grantedNeedsRestart: Binding(
                get: { [weak self] in self?.grantedNeedsRestart ?? false },
                set: { [weak self] in self?.grantedNeedsRestart = $0 }),
            onOpenSettings: { Permission.screenRecording.openSettings() },
            onRequest: { Permission.screenRecording.request() },
            onRelaunch: { AppRestart.relaunch() })
        install(NSHostingController(rootView: view))
        startPermissionWatch()
    }

    /// Polls the permission once per second. A window that stays unchanged after the
    /// switch was flipped looks broken.
    private func startPermissionWatch() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.grantedNeedsRestart else { return }
                guard Permission.screenRecording.isGranted else { return }
                self.grantedNeedsRestart = true
                self.showPermissionGate()   // now shows the restart hint
                self.permissionTimer?.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func showMainContent() {
        isShowingMainContent = true
        let picker = PickerView(
            registry: registry,
            selection: selection,
            onSelect: { [weak self] window in self?.select(window) },
            onRefresh: { [weak self] in Task { await self?.registry.refresh() } },
            onQuit: { NSApp.terminate(nil) })

        let pickerItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: picker))
        pickerItem.minimumThickness = 280
        pickerItem.maximumThickness = 420

        let mirror = MirrorViewController(capture: pin.capture)
        mirror.onToggleOverlay = { [weak self] in self?.toggleOverlay() }
        mirror.onPlayPause = { [weak self] in _ = self?.pin.send(.playPause) }
        mirror.onToggleMode = { [weak self] in self?.toggleModeFromUI() }
        pin.onPlacementChanged = { [weak self] in self?.updatePlacementStatus() }
        // The overlay can hide itself; every control showing its state must follow.
        pin.overlay.onCommand = { [weak self] command in _ = self?.pin.send(command) }
        pin.overlay.onCloseRequest = { [weak self] in
            self?.pin.hideOverlay()
            self?.mirrorController?.setOverlayVisible(false)
            self?.statusItem?.setOverlayVisible(false)
        }
        mirrorController = mirror
        let mirrorItem = NSSplitViewItem(viewController: mirror)

        let split = NSSplitViewController()
        split.addSplitViewItem(pickerItem)
        split.addSplitViewItem(mirrorItem)

        installHotkeys()
        install(split)
        // Through `refreshTask`, so the refresh that follows when the window comes to
        // the front does not fetch the same list a second time.
        refreshTask = Task { [weak self] in
            await self?.registry.refresh()
            self?.refreshTask = nil
            self?.applyAutoSelectionIfRequested()
        }
    }

    /// The menu bar item is the main way into AnyPlay.
    func installStatusItem() {
        let item = StatusItemController()
        item.onChooseWindow = { [weak self] in self?.bringWindowForward() }
        item.onToggleOverlay = { [weak self] in self?.toggleOverlay() }
        item.onToggleMode = { [weak self] in self?.toggleModeFromUI() }
        item.onPlayPause = { [weak self] in _ = self?.pin.send(.playPause) }
        item.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem = item
        DiagnosticLog.shared?.line("MENUBAR item installed: \(item.isInMenuBar)")

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .anyPlaySettingsChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applySettings() }
            }
    }

    func bringWindowForward() {
        AXBridge.bringSelfToFront()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // An already-key window posts no notification, so the refresh is triggered here
        // as well. Windows opened since the last look would otherwise stay missing.
        refreshWindowList()
        DiagnosticLog.shared?.line("WINDOW brought forward")
    }

    /// Only for --selftest-playpause: goes through the same path as the button and
    /// the hotkey.
    func sendPlayPauseForTest() {
        DiagnosticLog.shared?.line("TEST playPause: \(pin.send(.playPause))")
    }

    /// Only for --selftest-click: clicks the middle of the source window, so a script
    /// can find out whether a forwarded click arrives. Phase 0 measured that clicks
    /// never reached Safari; whether that also holds for the Picture-in-Picture window
    /// has to be measured, not assumed.
    func clickSourceCentreForTest() {
        guard let window = pin.capture.window else {
            DiagnosticLog.shared?.line("CLICK skipped: no source")
            return
        }
        let centre = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let ok = InputForwarder.click(at: centre, to: window.processID)
        DiagnosticLog.shared?.line("CLICK at \(centre) to pid \(window.processID): \(ok)")
        // The Accessibility API ignores window order entirely. If the source exposes
        // its controls as elements, they can be pressed from behind a fullscreen game —
        // which a posted click cannot.
        AXBridge.dumpTree(ofPID: window.processID)
    }

    func openSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController()
            controller.onHotkeysChanged = { [weak self] in self?.statusItem?.updateShortcutHints() }
            settingsWindow = controller
        }
        settingsWindow?.show()
    }

    /// Applies a changed frame rate or pointer setting to the running stream.
    private func applySettings() {
        Task { await pin.capture.applySettings() }
    }

    private func toggleModeFromUI() {
        pin.toggleMode()
        mirrorController?.setMode(pin.mode)
        statusItem?.setMode(pin.mode)
        updatePlacementStatus()
    }

    /// The shortcuts work system-wide, including while a game runs fullscreen.
    private func installHotkeys() {
        HotkeyCenter.shared.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleOverlay: self.toggleOverlay()
            case .toggleMode:    self.toggleModeFromUI()
            case .playPause:     _ = self.pin.send(.playPause)
            }
        }
        HotkeyCenter.shared.registerAll()
    }

    /// Reacts to whatever happens to the target window.
    private func installWatcher() {
        watcher.onFinding = { [weak self] finding in
            guard let self else { return }
            switch finding {
            case .fine:
                break
            case .wasMinimized:
                self.mirrorController?.setPlacement(L10n.tr("placement.wasMinimized"))
            case .rediscovered(let window):
                DiagnosticLog.shared?.line("Target window found again: \(window.title) (id \(window.windowID))")
                self.selection.set(window)
                Task { await self.pin.adopt(window) }
            case .gone:
                DiagnosticLog.shared?.line("Target window is gone — placeholder")
                self.pin.targetVanished()
                self.pin.overlay.showMessage(
                    L10n.tr("overlay.gone.message"),
                    actionTitle: L10n.tr("overlay.gone.action")) { [weak self] in
                        self?.bringWindowForward()
                    }
                Task { await self.pin.capture.stop() }
                self.watcher.stop()
            }
        }
        watcher.start(checking: pin)
    }

    /// Installs content and fixes the window size.
    ///
    /// `contentViewController` resizes the window to the content's preferred size —
    /// with SwiftUI content without fixed dimensions that produced a 95 × 1455 point
    /// window, taller than the display. So the size is set once, explicitly.
    private func install(_ controller: NSViewController) {
        guard let window else { return }
        window.contentViewController = controller
        guard !hasSizedWindow else { return }
        hasSizedWindow = true
        window.setContentSize(Self.defaultSize)
        window.center()
    }

    /// Development only: --select picks a window without a mouse click.
    private func applyAutoSelectionIfRequested() {
        guard LaunchOptions.current.hasAutoSelection,
              case .ready(let windows) = registry.state,
              let window = LaunchOptions.current.match(in: windows) else { return }
        select(window)
    }

    // MARK: Selection

    private func select(_ window: TargetWindow) {
        selection.set(window)
        pin.overlay.clearMessage()
        Task {
            await pin.start(window: window)
            self.installWatcher()
            if LaunchOptions.current.showOverlayImmediately {
                self.requestAccessibilityIfNeeded()
                self.pin.showOverlay()
                if LaunchOptions.current.runsInputSelftest { self.runInputSelftest() }
                self.mirrorController?.setOverlayVisible(true)
                self.statusItem?.setOverlayVisible(true)
            }
        }
    }

    private func toggleOverlay() {
        if !pin.overlay.isVisible { requestAccessibilityIfNeeded() }
        pin.toggleOverlay()
        mirrorController?.setOverlayVisible(pin.overlay.isVisible)
        statusItem?.setOverlayVisible(pin.overlay.isVisible)
        updatePlacementStatus()
    }

    /// Pinning needs Accessibility. If it is missing, the first attempt opens the
    /// system prompt — after that AnyPlay is in the list and one switch remains.
    private func requestAccessibilityIfNeeded() {
        guard LaunchOptions.current.placesTargetWindow,
              !AXBridge.isTrusted(prompt: false) else { return }
        _ = AXBridge.isTrusted(prompt: true)
    }

    /// Checks switching into input mode and back without a mouse. It deliberately does
    /// not send key presses: a self-test that changes other apps' data has no place
    /// inside the app.
    private func runInputSelftest() {
        Task { @MainActor in
            let log = DiagnosticLog.shared
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            log?.line("SELFTEST input mode on (expected: front = target app)")
            pin.enterInputMode()
            mirrorController?.setMode(pin.mode)
            updatePlacementStatus()

            try? await Task.sleep(nanoseconds: 5_000_000_000)
            log?.line("SELFTEST input mode off (expected: front = previous app)")
            pin.leaveInputMode()
            mirrorController?.setMode(pin.mode)
            updatePlacementStatus()
        }
    }

    /// Called when quitting.
    func restorePinnedWindows() {
        for session in pins.sessions { session.unpinTargetWindow() }
    }

    private func updatePlacementStatus() {
        let text: String?
        switch pin.placement {
        case .detached:
            text = pin.overlay.isVisible ? L10n.tr("placement.notPinned") : nil
        case .failed(let message):
            text = message
        case .placed(let actual, _) where pin.mode == .input:
            text = L10n.tr("placement.inputMode", Int(actual.width), Int(actual.height))
        case .placed(let actual, _):
            if pin.placement.mismatch != nil {
                text = L10n.tr("placement.minimum", Int(actual.width), Int(actual.height))
            } else {
                text = L10n.tr("placement.ok")
            }
        }
        mirrorController?.setPlacement(text)
    }
}
