// SingleInstance.swift — there is only ever one AnyPlay.
//
// Two instances would register the same global shortcuts (the second registration
// fails silently) and could pin the same window twice. So a second launch does not
// start a second app: it asks the running one to show its window and quits.

import AppKit

enum SingleInstance {

    static let showWindowNotification = Notification.Name("com.normanaugscheller.anyplay.showWindow")

    /// Returns true if another AnyPlay is already running. In that case it has been
    /// asked to bring its window forward, and the caller should quit.
    static func handOverIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        guard !others.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
        return true
    }

    /// Called by the running instance: react when a second launch knocks.
    static func observeHandOver(_ handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: showWindowNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
    }
}
