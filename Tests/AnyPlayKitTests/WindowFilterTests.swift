import Testing
import CoreGraphics
@testable import AnyPlayKit

@Suite("Which windows are offered")
struct WindowFilterTests {

    func candidate(layer: Int = 0, width: CGFloat = 800, height: CGFloat = 600,
                   title: String? = "Page", onScreen: Bool = true,
                   bundleID: String? = "com.apple.Safari", hasOwner: Bool = true) -> WindowCandidate {
        WindowCandidate(layer: layer, frame: CGRect(x: 0, y: 0, width: width, height: height),
                        title: title, isOnScreen: onScreen, bundleID: bundleID,
                        hasOwningApplication: hasOwner)
    }

    @Test("An ordinary visible window is offered")
    func acceptsOrdinaryWindow() {
        #expect(WindowFilter.isUsable(candidate(), ownBundleID: "me"))
    }

    @Test("Menu bar items and overlays on other layers are not")
    func rejectsOtherLayers() {
        #expect(!WindowFilter.isUsable(candidate(layer: 25), ownBundleID: "me"))
    }

    @Test("Toolbar strips and small helpers are not")
    func rejectsSmallWindows() {
        #expect(!WindowFilter.isUsable(candidate(width: 1470, height: 33), ownBundleID: "me"))
        #expect(!WindowFilter.isUsable(candidate(width: 64, height: 64), ownBundleID: "me"))
    }

    @Test("Safari's untitled 500 × 500 leftover is not offered")
    func rejectsSafariLeftover() {
        #expect(!WindowFilter.isUsable(candidate(width: 500, height: 500, title: "", onScreen: false),
                                       ownBundleID: "me"))
    }

    @Test("An untitled window that is actually visible stays")
    func keepsVisibleUntitledWindow() {
        #expect(WindowFilter.isUsable(candidate(title: "", onScreen: true), ownBundleID: "me"))
    }

    @Test("A titled window in another Space stays — that is where the target lives during a game")
    func keepsTitledWindowInOtherSpace() {
        #expect(WindowFilter.isUsable(candidate(title: "YouTube", onScreen: false), ownBundleID: "me"))
    }

    @Test("AnyPlay never offers its own windows")
    func rejectsOwnWindows() {
        #expect(!WindowFilter.isUsable(candidate(bundleID: "me"), ownBundleID: "me"))
    }

    @Test("A window without an owning app is not offered")
    func rejectsOwnerlessWindow() {
        #expect(!WindowFilter.isUsable(candidate(hasOwner: false), ownBundleID: "me"))
    }
}
