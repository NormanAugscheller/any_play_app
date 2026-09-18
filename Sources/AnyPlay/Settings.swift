// Settings.swift — what can be configured.
//
// Deliberately plain: UserDefaults plus a notification when something changes. A
// model object with bindings would be more scaffolding than use for four values.

import Foundation

extension Notification.Name {
    static let anyPlaySettingsChanged = Notification.Name("anyPlaySettingsChanged")
}

enum Settings {

    /// Upper limit for the frame rate. 60 by default; 120 only makes sense on a
    /// display that can show it, 30 saves noticeable work while a game is running.
    static let allowedFPS = [30, 60, 120]

    static var maximumFPS: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "maximumFPS")
            return allowedFPS.contains(stored) ? stored : 60
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "maximumFPS")
            notifyChange()
        }
    }

    static var showsCursor: Bool {
        get { UserDefaults.standard.bool(forKey: "showsCursor") }
        set {
            UserDefaults.standard.set(newValue, forKey: "showsCursor")
            notifyChange()
        }
    }

    /// Places the real window beneath the overlay while pinned. Turn it off to only
    /// mirror — the foreign window then stays where it is.
    static var placesTargetWindow: Bool {
        get { UserDefaults.standard.object(forKey: "placesTargetWindow") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "placesTargetWindow")
            notifyChange()
        }
    }

    static var captureSettings: CaptureSettings {
        CaptureSettings(maximumFPS: maximumFPS, showsCursor: showsCursor)
    }

    private static func notifyChange() {
        NotificationCenter.default.post(name: .anyPlaySettingsChanged, object: nil)
    }
}
