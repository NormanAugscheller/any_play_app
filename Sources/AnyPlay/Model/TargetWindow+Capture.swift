// TargetWindow+Capture.swift — building a TargetWindow from ScreenCaptureKit.

import ScreenCaptureKit
import AnyPlayKit

extension TargetWindow {

    init?(_ window: SCWindow) {
        guard let app = window.owningApplication else { return nil }
        self.init(windowID: window.windowID,
                  processID: app.processID,
                  bundleID: app.bundleIdentifier,
                  appName: app.applicationName,
                  title: window.title ?? "",
                  frame: window.frame,
                  isOnScreen: window.isOnScreen)
    }

    /// What the list shows for a window without a title.
    var displayTitle: String {
        title.isEmpty ? L10n.tr("window.untitled") : title
    }
}

extension WindowCandidate {
    init(_ window: SCWindow) {
        self.init(layer: window.windowLayer,
                  frame: window.frame,
                  title: window.title,
                  isOnScreen: window.isOnScreen,
                  bundleID: window.owningApplication?.bundleIdentifier,
                  hasOwningApplication: window.owningApplication != nil)
    }
}
