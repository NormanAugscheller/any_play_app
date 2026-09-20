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

    // MARK: Picture-in-Picture
    //
    // The best source AnyPlay has: only the video, and drawn on every Space. It does
    // not sit on the normal window layer, so without an exception the filter would
    // throw away the one window the app most wants. Measured on the real system:
    // layer 19, 493 x 258, bundle com.apple.PIPAgent.

    func pictureInPicture(width: CGFloat = 493, height: CGFloat = 258) -> WindowCandidate {
        candidate(layer: 19, width: width, height: height, title: "Bild-in-Bild",
                  bundleID: WindowFilter.pictureInPictureBundleID)
    }

    @Test("The system Picture-in-Picture window is offered although it is not on layer 0")
    func acceptsPictureInPicture() {
        #expect(WindowFilter.isUsable(pictureInPicture(), ownBundleID: "me"))
    }

    @Test("Another window on layer 19 is still rejected")
    func rejectsOtherWindowsOnTheSameLayer() {
        #expect(!WindowFilter.isUsable(candidate(layer: 19), ownBundleID: "me"))
    }

    @Test("A Picture-in-Picture dragged small stays usable, a flat 16:9 picture included")
    func acceptsSmallPictureInPicture() {
        #expect(WindowFilter.isUsable(pictureInPicture(width: 250, height: 140), ownBundleID: "me"))
        #expect(WindowFilter.isUsable(pictureInPicture(width: 300, height: 169), ownBundleID: "me"))
    }

    @Test("Below the Picture-in-Picture minimum it is dropped as well")
    func rejectsTinyPictureInPicture() {
        #expect(!WindowFilter.isUsable(pictureInPicture(width: 200, height: 112), ownBundleID: "me"))
    }
}
