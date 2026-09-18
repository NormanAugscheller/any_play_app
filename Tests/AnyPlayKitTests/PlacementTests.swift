import Testing
import Foundation
import CoreGraphics
@testable import AnyPlayKit

@Suite("Placement state")
struct PlacementStateTests {

    @Test("No mismatch when the app accepted the requested size")
    func noMismatchWhenExact() {
        let rect = CGRect(x: 850, y: 72, width: 574, height: 279)
        #expect(PlacementState.placed(actual: rect, requested: rect).mismatch == nil)
    }

    @Test("Safari's minimum width shows up as a mismatch of +74 points")
    func reportsSafariMinimum() {
        let requested = CGRect(x: 850, y: 72, width: 500, height: 279)
        let actual = CGRect(x: 850, y: 72, width: 574, height: 279)
        #expect(PlacementState.placed(actual: actual, requested: requested).mismatch
                == CGSize(width: 74, height: 0))
    }

    @Test("Only a placed state counts as placed")
    func reportsPlaced() {
        #expect(!PlacementState.detached.isPlaced)
        #expect(!PlacementState.failed("x").isPlaced)
        #expect(PlacementState.placed(actual: .zero, requested: .zero).isPlaced)
    }
}

@Suite("Placement journal")
struct PlacementJournalTests {

    func temporaryJournal() -> (PlacementJournal, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnyPlayTests-\(UUID().uuidString)")
        return (PlacementJournal(directory: directory), directory)
    }

    let record = PlacementRecord(processID: 42, bundleID: "com.apple.Safari", windowTitle: "YouTube",
                                 originalFrame: CGRect(x: 117, y: 110, width: 1300, height: 727),
                                 pinnedFrame: CGRect(x: 850, y: 72, width: 574, height: 279))

    @Test("A written entry survives on disk and can be read back")
    func persists() {
        let (journal, directory) = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: directory) }
        journal.set(record, for: "pin")
        // A fresh instance reads the same file — as the next launch after a crash would.
        #expect(PlacementJournal(directory: directory).all() == ["pin": record])
    }

    @Test("Removing the last entry deletes the file")
    func cleansUp() {
        let (journal, directory) = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: directory) }
        journal.set(record, for: "pin")
        journal.remove("pin")
        #expect(journal.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("placements.json").path))
    }

    @Test("A window still sitting where AnyPlay left it is restored")
    func restoresUntouchedWindow() {
        #expect(PlacementJournal.shouldRestore(record, currentFrame: record.pinnedFrame))
        // Two points of snapping are tolerated.
        let snapped = record.pinnedFrame.offsetBy(dx: 2, dy: -1)
        #expect(PlacementJournal.shouldRestore(record, currentFrame: snapped))
    }

    @Test("A window someone has moved since is left alone")
    func respectsUserChanges() {
        let moved = record.pinnedFrame.offsetBy(dx: 200, dy: 0)
        #expect(!PlacementJournal.shouldRestore(record, currentFrame: moved))
        let resized = CGRect(origin: record.pinnedFrame.origin, size: CGSize(width: 900, height: 600))
        #expect(!PlacementJournal.shouldRestore(record, currentFrame: resized))
    }
}
