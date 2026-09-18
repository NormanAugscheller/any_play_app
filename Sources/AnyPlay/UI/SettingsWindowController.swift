// SettingsWindowController.swift — settings.
//
// Hand-built AppKit rather than SwiftUI: recording a shortcut needs raw keyboard
// events, and an NSWindow with a local event monitor is the direct way to get them.

import AppKit
import Carbon.HIToolbox
import AnyPlayKit

@MainActor
final class SettingsWindowController: NSWindowController {

    private let fpsControl = NSSegmentedControl(labels: Settings.allowedFPS.map { "\($0)" },
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let cursorCheckbox = NSButton(checkboxWithTitle: L10n.tr("settings.cursor"),
                                          target: nil, action: nil)
    private let placeCheckbox = NSButton(checkboxWithTitle: L10n.tr("settings.place"),
                                         target: nil, action: nil)
    private var hotkeyRows: [HotkeyAction: (field: NSTextField, button: NSButton)] = [:]
    private var captureMonitor: Any?
    private var capturingAction: HotkeyAction?

    /// Called when a shortcut changed.
    var onHotkeysChanged: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = L10n.tr("settings.title")
        window.center()
        super.init(window: window)
        window.contentView = buildContent()
        readValues()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private func buildContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16                      // 8-point grid
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(headline(L10n.tr("settings.section.picture")))

        let fpsRow = NSStackView(views: [label(L10n.tr("settings.fps")), fpsControl])
        fpsRow.spacing = 8
        fpsControl.target = self
        fpsControl.action = #selector(fpsChanged)
        stack.addArrangedSubview(fpsRow)

        cursorCheckbox.target = self
        cursorCheckbox.action = #selector(cursorChanged)
        stack.addArrangedSubview(cursorCheckbox)

        placeCheckbox.target = self
        placeCheckbox.action = #selector(placeChanged)
        stack.addArrangedSubview(placeCheckbox)

        stack.addArrangedSubview(headline(L10n.tr("settings.section.shortcuts")))
        for action in HotkeyAction.allCases {
            stack.addArrangedSubview(hotkeyRow(for: action))
        }

        let resetButton = NSButton(title: L10n.tr("settings.reset"),
                                   target: self, action: #selector(resetHotkeys))
        stack.addArrangedSubview(resetButton)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        return container
    }

    private func headline(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .boldSystemFont(ofSize: 13)
        return field
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func hotkeyRow(for action: HotkeyAction) -> NSView {
        let name = label(action.label)
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let field = NSTextField(labelWithString: HotkeyCenter.shared.shortcut(for: action).display)
        field.alignment = .right
        field.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        let button = NSButton(title: L10n.tr("settings.change"), target: self,
                              action: #selector(startCapture(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)

        hotkeyRows[action] = (field, button)
        let row = NSStackView(views: [name, field, button])
        row.spacing = 8
        row.alignment = .firstBaseline
        NSLayoutConstraint.activate([
            name.widthAnchor.constraint(equalToConstant: 180),
            field.widthAnchor.constraint(equalToConstant: 110),
        ])
        return row
    }

    private func readValues() {
        fpsControl.selectedSegment = Settings.allowedFPS.firstIndex(of: Settings.maximumFPS) ?? 1
        cursorCheckbox.state = Settings.showsCursor ? .on : .off
        placeCheckbox.state = Settings.placesTargetWindow ? .on : .off
        refreshHotkeyFields()
    }

    private func refreshHotkeyFields() {
        for (action, row) in hotkeyRows {
            row.field.stringValue = HotkeyCenter.shared.shortcut(for: action).display
            row.button.title = L10n.tr("settings.change")
        }
    }

    // MARK: Values

    @objc private func fpsChanged() {
        let index = fpsControl.selectedSegment
        guard index >= 0, index < Settings.allowedFPS.count else { return }
        Settings.maximumFPS = Settings.allowedFPS[index]
    }

    @objc private func cursorChanged() {
        Settings.showsCursor = (cursorCheckbox.state == .on)
    }

    @objc private func placeChanged() {
        Settings.placesTargetWindow = (placeCheckbox.state == .on)
    }

    @objc private func resetHotkeys() {
        HotkeyCenter.shared.resetToDefaults()
        refreshHotkeyFields()
        onHotkeysChanged?()
    }

    // MARK: Recording a shortcut

    @objc private func startCapture(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let action = HotkeyAction(rawValue: raw) else { return }
        // A second click on the same button cancels.
        if capturingAction == action {
            stopCapture()
            refreshHotkeyFields()
            return
        }
        stopCapture()
        capturingAction = action
        hotkeyRows[action]?.field.stringValue = L10n.tr("settings.pressKeys")
        sender.title = L10n.tr("settings.cancel")

        // While recording, the old shortcuts must not fire — a registered hotkey would
        // swallow exactly the key press this is waiting for.
        HotkeyCenter.shared.unregisterAll()
        DiagnosticLog.shared?.line("SETTINGS recording \(action.rawValue)")
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.stopCapture()
                self.refreshHotkeyFields()
                return nil
            }
            guard let shortcut = Shortcut(keyCode: event.keyCode,
                                          modifierFlags: event.modifierFlags,
                                          characters: event.charactersIgnoringModifiers) else {
                // Without a modifier the shortcut would get in the way system-wide.
                self.hotkeyRows[action]?.field.stringValue = L10n.tr("settings.needsModifier")
                return nil
            }
            HotkeyCenter.shared.setShortcut(shortcut, for: action)
            DiagnosticLog.shared?.line("SETTINGS recorded \(action.rawValue) = \(shortcut.display)")
            self.stopCapture()
            self.refreshHotkeyFields()
            self.onHotkeysChanged?()
            return nil
        }
    }

    private func stopCapture() {
        if let monitor = captureMonitor { NSEvent.removeMonitor(monitor) }
        captureMonitor = nil
        capturingAction = nil
        HotkeyCenter.shared.registerAll()
    }

    func show() {
        readValues()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        AXBridge.bringSelfToFront()
    }
}
