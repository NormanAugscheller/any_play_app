// PlacementJournal.swift — remembers where a pinned window came from, on disk.
//
// AnyPlay puts a foreign window back when it quits normally and when it receives
// SIGTERM. A crash skips both, and the original size would be lost because it only
// lived in memory. So it is written to disk the moment a window is pinned and
// removed when it is put back. Whatever is still in the journal at the next launch
// belongs to a run that did not clean up.

import Foundation
import CoreGraphics

public struct PlacementRecord: Codable, Equatable, Sendable {
    public var processID: pid_t
    public var bundleID: String?
    public var windowTitle: String
    /// Where the window was before AnyPlay touched it. Window-server coordinates.
    public var originalFrame: CGRect
    /// Where AnyPlay last put it.
    public var pinnedFrame: CGRect

    public init(processID: pid_t, bundleID: String?, windowTitle: String,
                originalFrame: CGRect, pinnedFrame: CGRect) {
        self.processID = processID
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.originalFrame = originalFrame
        self.pinnedFrame = pinnedFrame
    }
}

public final class PlacementJournal: @unchecked Sendable {

    private let fileURL: URL
    private let lock = NSLock()

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("placements.json")
    }

    /// ~/Library/Application Support/AnyPlay/placements.json
    public static let standard: PlacementJournal = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PlacementJournal(directory: base.appendingPathComponent("AnyPlay"))
    }()

    public func all() -> [String: PlacementRecord] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    public func set(_ record: PlacementRecord, for key: String) {
        lock.lock(); defer { lock.unlock() }
        var records = load()
        records[key] = record
        save(records)
    }

    public func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        var records = load()
        records.removeValue(forKey: key)
        save(records)
    }

    /// A window is only put back if it still sits where AnyPlay left it. If someone
    /// has moved or resized it since, their decision wins.
    public static func shouldRestore(_ record: PlacementRecord, currentFrame: CGRect,
                                     tolerance: CGFloat = 3) -> Bool {
        abs(currentFrame.origin.x - record.pinnedFrame.origin.x) < tolerance
            && abs(currentFrame.origin.y - record.pinnedFrame.origin.y) < tolerance
            && abs(currentFrame.width - record.pinnedFrame.width) < tolerance
            && abs(currentFrame.height - record.pinnedFrame.height) < tolerance
    }

    private func load() -> [String: PlacementRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([String: PlacementRecord].self, from: data)
        else { return [:] }
        return records
    }

    private func save(_ records: [String: PlacementRecord]) {
        if records.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
