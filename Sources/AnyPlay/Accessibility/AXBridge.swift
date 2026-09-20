// AXBridge.swift — the narrow gateway to the Accessibility API.
//
// The C API of ApplicationServices works with CFTypeRef and output pointers.
// Everything above this file should work with Swift types, so the translation
// happens in exactly one place.

import AppKit
import ApplicationServices
import AnyPlayKit

enum AXBridge {

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func windows(ofPID pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        guard let value = copy(app, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return value
    }

    /// Writes what an app offers the Accessibility API into the diagnostic log.
    /// Diagnosis only — it answers whether a control can be pressed without the window
    /// being in front.
    static func dumpTree(ofPID pid: pid_t, depth: Int = 4) {
        let app = AXUIElementCreateApplication(pid)
        DiagnosticLog.shared?.line("AX tree of pid \(pid):")
        describe(app, indent: 0, remaining: depth)
    }

    private static func describe(_ element: AXUIElement, indent: Int, remaining: Int) {
        guard remaining > 0 else { return }
        let role = string(element, kAXRoleAttribute as String) ?? "?"
        let title = string(element, kAXTitleAttribute as String)
            ?? string(element, kAXDescriptionAttribute as String) ?? ""
        var actionsRef: CFArray?
        AXUIElementCopyActionNames(element, &actionsRef)
        let actions = (actionsRef as? [String]) ?? []
        let pad = String(repeating: "  ", count: indent)
        let identifier = string(element, kAXIdentifierAttribute as String) ?? "-"
        let origin = point(element, kAXPositionAttribute as String) ?? .zero
        let extent = size(element, kAXSizeAttribute as String) ?? .zero
        DiagnosticLog.shared?.line("\(pad)\(role) \"\(title)\" id=\(identifier) "
            + "at \(Int(origin.x)),\(Int(origin.y)) \(Int(extent.width))x\(Int(extent.height)) "
            + "actions=\(actions.joined(separator: ","))")
        let children = (copy(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
        for child in children.prefix(30) {
            describe(child, indent: indent + 1, remaining: remaining - 1)
        }
    }

    /// Searches an app's Accessibility tree for pressable elements whose label
    /// contains `needle`. Diagnosis only: it answers whether a button inside a web
    /// page can be reached — and whether that still holds when the window sits on
    /// another Space.
    ///
    /// A web page produces a deep and wide tree, so the walk is bounded. Without a
    /// budget this runs for minutes on a YouTube page.
    static func find(_ needle: String, inPID pid: pid_t,
                     maximumNodes: Int = 40_000, maximumDepth: Int = 40) {
        let app = AXUIElementCreateApplication(pid)
        // WebKit only builds the Accessibility tree for the page once a client asks
        // for it. Without this the walk sees the toolbar and stops: measured, 684
        // nodes and not one element of the page.
        let enabled = AXUIElementSetAttributeValue(
            app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
        DiagnosticLog.shared?.line("AXFIND manual accessibility set: \(enabled)")
        var visited = 0
        var hits = 0
        var stack: [(element: AXUIElement, depth: Int)] = [(app, 0)]
        while let (element, depth) = stack.popLast(), visited < maximumNodes {
            visited += 1
            let label = [string(element, kAXTitleAttribute as String),
                         string(element, kAXDescriptionAttribute as String),
                         string(element, kAXValueAttribute as String)]
                .compactMap { $0 }.joined(separator: " | ")
            if label.localizedCaseInsensitiveContains(needle) {
                var actionsRef: CFArray?
                AXUIElementCopyActionNames(element, &actionsRef)
                let actions = (actionsRef as? [String]) ?? []
                let role = string(element, kAXRoleAttribute as String) ?? "?"
                DiagnosticLog.shared?.line("AXFIND depth=\(depth) \(role) \"\(label)\" "
                                         + "actions=\(actions.joined(separator: ","))")
                hits += 1
            }
            guard depth < maximumDepth,
                  let children = copy(element, kAXChildrenAttribute as String) as? [AXUIElement]
            else { continue }
            for child in children { stack.append((child, depth + 1)) }
        }
        DiagnosticLog.shared?.line("AXFIND \"\(needle)\" in pid \(pid): "
                                 + "\(hits) hits, \(visited) nodes visited")
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
            ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copy(element, attribute) as? Bool
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &result) else { return nil }
        return result
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &result) else { return nil }
        return result
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, point: CGPoint) -> Bool {
        var value = point
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, axValue) == .success
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, size: CGSize) -> Bool {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, axValue) == .success
    }

    /// Brings an app to the front.
    ///
    /// `NSRunningApplication.activate()` is not enough: since macOS 14 an app may only
    /// hand over focus while it has focus itself. When leaving input mode the target
    /// app is in front and AnyPlay in the background — the request is then silently
    /// refused. Measured: after leaving, Safari stayed in front. Through the
    /// Accessibility API it works, because that is not bound to activation rights.
    @discardableResult
    static func bringToFront(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        return AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString,
                                            kCFBooleanTrue) == .success
    }

    /// Brings AnyPlay itself to the front.
    ///
    /// Since macOS 14, `NSApp.activate` is a request that the system may decline when it
    /// does not follow a user action inside AnyPlay — opening the window because a second
    /// launch knocked is such a case. The Accessibility route is not bound to activation
    /// rights; for switching back from input mode it was measured to work where
    /// `activate()` silently did nothing. Here it is a second line, used when available.
    static func bringSelfToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if isTrusted(prompt: false) {
            bringToFront(pid: ProcessInfo.processInfo.processIdentifier)
        }
    }

    /// Frame of an AX window, in window-server coordinates (top left origin).
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute as String),
              let size = size(window, kAXSizeAttribute as String) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

/// Connects ScreenGeometry to the displays that are actually attached.
enum ScreenCoordinates {

    /// Height of the display holding the origin of the global coordinate space —
    /// `NSScreen.screens[0]`, the one with the menu bar. Not `NSScreen.main`, which
    /// is merely the display with the key window.
    private static var referenceHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func windowServerRect(fromAppKit rect: NSRect) -> CGRect {
        ScreenGeometry.flip(rect, referenceHeight: referenceHeight)
    }

    static func appKitRect(fromWindowServer rect: CGRect) -> NSRect {
        ScreenGeometry.flip(rect, referenceHeight: referenceHeight)
    }

    /// Pixels per point of the display a window-server rectangle mostly lies on.
    static func backingScale(forWindowServerRect rect: CGRect) -> CGFloat {
        let displays = NSScreen.screens.map {
            ScreenGeometry.Display(frame: $0.frame, backingScale: $0.backingScaleFactor)
        }
        return ScreenGeometry.backingScale(for: appKitRect(fromWindowServer: rect),
                                           displays: displays,
                                           fallback: NSScreen.main?.backingScaleFactor ?? 2)
    }
}
