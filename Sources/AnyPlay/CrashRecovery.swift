// CrashRecovery.swift — puts back windows that a crashed run left displaced.

import AppKit
import AnyPlayKit

@MainActor
enum CrashRecovery {

    /// Goes through the journal. Every entry belongs to a run that pinned a window and
    /// never put it back. A window is restored only if it still sits exactly where
    /// that run left it — if someone has moved it since, their decision wins.
    static func restoreLeftovers(from journal: PlacementJournal) {
        let leftovers = journal.all()
        guard !leftovers.isEmpty else { return }
        // Without Accessibility nothing can be moved. Keep the entries for a later
        // launch instead of throwing the original sizes away.
        guard AXBridge.isTrusted(prompt: false) else {
            DiagnosticLog.shared?.line("RECOVERY \(leftovers.count) entries kept: no Accessibility permission")
            return
        }
        for (key, record) in leftovers {
            let restored = restore(record)
            DiagnosticLog.shared?.line("RECOVERY \(record.windowTitle): "
                + (restored ? "restored to \(record.originalFrame)" : "left alone"))
            journal.remove(key)
        }
    }

    private static func restore(_ record: PlacementRecord) -> Bool {
        // The app may have been restarted since, with a new process ID.
        var pids: [pid_t] = [record.processID]
        if let bundleID = record.bundleID {
            pids += NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .map(\.processIdentifier)
        }
        for pid in Set(pids) {
            for window in AXBridge.windows(ofPID: pid) {
                guard let frame = AXBridge.frame(window),
                      PlacementJournal.shouldRestore(record, currentFrame: frame) else { continue }
                // Same two-pass placement as everywhere else, for the same reason.
                for _ in 0..<2 {
                    AXBridge.set(window, kAXPositionAttribute as String, point: record.originalFrame.origin)
                    AXBridge.set(window, kAXSizeAttribute as String, size: record.originalFrame.size)
                }
                return true
            }
        }
        return false
    }
}
