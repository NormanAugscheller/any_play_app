// DiagnosticLog.swift — a state log for development, enabled with --log.
//
// It exists because behaviour over a fullscreen game cannot be watched: the app's
// own window is in another Space then. Not needed in normal use.

import Foundation
import AnyPlayKit

final class DiagnosticLog {
    static let shared: DiagnosticLog? = {
        guard let path = LaunchOptions.current.logPath else { return nil }
        return DiagnosticLog(path: path)
    }()

    private let handle: FileHandle
    private let queue = DispatchQueue(label: "com.normanaugscheller.anyplay.log")
    private let start = Date()
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private init?(path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        self.handle = handle
    }

    func line(_ text: String) {
        let stamp = String(format: "%@ %7.3f  ", Self.clock.string(from: Date()),
                           Date().timeIntervalSince(start))
        queue.async { [handle] in
            if let data = (stamp + text + "\n").data(using: .utf8) { handle.write(data) }
        }
    }
}
