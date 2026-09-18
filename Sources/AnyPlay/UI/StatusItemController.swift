// StatusItemController.swift — AnyPlay in the menu bar.
//
// AnyPlay runs as .accessory, without a Dock icon; this menu is its main entry point.

import AppKit

@MainActor
final class StatusItemController {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    /// What the menu can trigger. The work itself stays with the window controller.
    var onChooseWindow: (() -> Void)?
    var onToggleOverlay: (() -> Void)?
    var onToggleMode: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let overlayItem = NSMenuItem()
    private let modeItem = NSMenuItem()
    private var overlayVisible = false
    private var mode: PinMode = .passive

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                   accessibilityDescription: "AnyPlay")
            // If the symbol is missing on this system version, text beats nothing.
            if button.image == nil { button.title = "AnyPlay" }
        }
        buildMenu()
        statusItem.menu = menu
    }

    private func buildMenu() {
        let chooseItem = NSMenuItem(title: L10n.tr("statusMenu.chooseWindow"),
                                    action: #selector(chooseWindow), keyEquivalent: "")
        chooseItem.target = self
        menu.addItem(chooseItem)
        menu.addItem(.separator())

        overlayItem.action = #selector(toggleOverlay)
        overlayItem.target = self
        menu.addItem(overlayItem)

        modeItem.action = #selector(toggleMode)
        modeItem.target = self
        menu.addItem(modeItem)

        let playItem = NSMenuItem(title: L10n.tr("action.playPause"),
                                  action: #selector(playPause), keyEquivalent: "")
        playItem.target = self
        menu.addItem(playItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L10n.tr("statusMenu.settings"),
                                      action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: L10n.tr("menu.quit"),
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        updateShortcutHints()
    }

    /// Writes the current shortcuts next to the entries, so they can be discovered.
    func updateShortcutHints() {
        let overlayTitle = overlayVisible ? L10n.tr("action.hideOverlay") : L10n.tr("action.showOverlay")
        overlayItem.title = overlayTitle + "   " + HotkeyCenter.shared.shortcut(for: .toggleOverlay).display
        let modeTitle = mode == .passive ? L10n.tr("action.inputMode") : L10n.tr("action.backToGame")
        modeItem.title = modeTitle + "   " + HotkeyCenter.shared.shortcut(for: .toggleMode).display
    }

    func setOverlayVisible(_ visible: Bool) {
        overlayVisible = visible
        updateShortcutHints()
    }

    func setMode(_ mode: PinMode) {
        self.mode = mode
        updateShortcutHints()
    }

    /// Is the item really in the menu bar? A status item without a window would exist
    /// but be invisible — that could not be told apart otherwise.
    var isInMenuBar: Bool { statusItem.button?.window != nil }

    @objc private func chooseWindow() { onChooseWindow?() }
    @objc private func toggleOverlay() { onToggleOverlay?() }
    @objc private func toggleMode() { onToggleMode?() }
    @objc private func playPause() { onPlayPause?() }
    @objc private func openSettings() { onOpenSettings?() }
}
