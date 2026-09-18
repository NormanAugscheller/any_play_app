import Testing
import CoreGraphics
@testable import AnyPlayKit

@Suite("Finding a pinned window again")
struct RediscoveryTests {

    func window(id: CGWindowID, pid: pid_t = 100, title: String) -> TargetWindow {
        TargetWindow(windowID: id, processID: pid, bundleID: "com.apple.finder", appName: "Finder",
                     title: title, frame: CGRect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true)
    }

    @Test("A window with the same process and title but a new ID is found again")
    func findsRebuiltWindow() {
        let pinned = window(id: 1, title: "Docs")
        let rebuilt = window(id: 2, title: "Docs")
        #expect(Rediscovery.find(pinned, in: [rebuilt]) == rebuilt)
    }

    @Test("Another window of the same app is NEVER taken instead — the placeholder rule")
    func neverTakesTheWindowBehind() {
        // The bug this guards against: closing the pinned window while another window
        // of the same app is open silently switched the overlay to that other window.
        let pinned = window(id: 1, title: "Docs")
        let other = window(id: 2, title: "Downloads")
        #expect(Rediscovery.find(pinned, in: [other]) == nil)
    }

    @Test("A window with the same title in a different app is not taken")
    func requiresSameProcess() {
        let pinned = window(id: 1, pid: 100, title: "Docs")
        let lookalike = window(id: 2, pid: 200, title: "Docs")
        #expect(Rediscovery.find(pinned, in: [lookalike]) == nil)
    }

    @Test("The vanished window itself is not 'found' again")
    func ignoresSameID() {
        let pinned = window(id: 1, title: "Docs")
        #expect(Rediscovery.find(pinned, in: [pinned]) == nil)
    }

    @Test("An untitled window cannot be identified and is not rediscovered")
    func refusesUntitled() {
        let pinned = window(id: 1, title: "")
        let other = window(id: 2, title: "")
        #expect(Rediscovery.find(pinned, in: [other]) == nil)
    }
}
