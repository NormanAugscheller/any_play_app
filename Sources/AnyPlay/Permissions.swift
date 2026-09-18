// Permissions.swift — checking, requesting and explaining permissions.
//
// AnyPlay needs two: Screen Recording (without it there is no picture) and
// Accessibility (to move other apps' windows). Neither may ever lead to a silent
// black picture — so they are their own, queryable state here and not a side effect
// buried in the capture code.

import AppKit
import ApplicationServices
import CoreGraphics

enum Permission: CaseIterable {
    case screenRecording
    case accessibility

    var title: String {
        switch self {
        case .screenRecording: return L10n.tr("permission.screenRecording.title")
        case .accessibility:   return L10n.tr("permission.accessibility.title")
        }
    }

    var reason: String {
        switch self {
        case .screenRecording: return L10n.tr("permission.screenRecording.reason")
        case .accessibility:   return L10n.tr("permission.accessibility.reason")
        }
    }

    /// Where to send the user in System Settings.
    var settingsURL: URL {
        switch self {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }

    var isGranted: Bool {
        switch self {
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .accessibility:   return AXIsProcessTrusted()
        }
    }

    /// Opens the system prompt. For Screen Recording this is also what adds the app
    /// to the list in System Settings in the first place.
    func request() {
        switch self {
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}

enum AppRestart {
    /// A freshly granted Screen Recording permission does not reach the running
    /// process — macOS decides at launch. So AnyPlay restarts itself instead of
    /// leaving the user with a black picture.
    ///
    /// The new instance is started by a tiny shell that first waits for this process
    /// to exit. Starting it directly would make it meet this still-running instance,
    /// and the single-instance rule would make it quit immediately.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"\(path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }
}
