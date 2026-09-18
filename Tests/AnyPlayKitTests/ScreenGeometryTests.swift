import Testing
import CoreGraphics
@testable import AnyPlayKit

@Suite("Screen geometry")
struct ScreenGeometryTests {

    // A MacBook Air display: 1470 × 956 points.
    let height: CGFloat = 956

    @Test("A window at the top left of the window server is at the top of AppKit's space")
    func flipsKnownValue() {
        let windowServer = CGRect(x: 117, y: 110, width: 1300, height: 727)
        let appKit = ScreenGeometry.flip(windowServer, referenceHeight: height)
        #expect(appKit == CGRect(x: 117, y: 956 - 110 - 727, width: 1300, height: 727))
    }

    @Test("Converting there and back returns the original rectangle")
    func roundTrips() {
        let rects = [CGRect(x: 850, y: 72, width: 574, height: 279),
                     CGRect(x: 0, y: 0, width: 1470, height: 956),
                     CGRect(x: -1920, y: -300, width: 800, height: 600)]
        for rect in rects {
            let back = ScreenGeometry.flip(ScreenGeometry.flip(rect, referenceHeight: height),
                                           referenceHeight: height)
            #expect(back == rect)
        }
    }

    @Test("A window on a second monitor to the left keeps its negative x and flips vertically")
    func handlesSecondMonitor() {
        // An external display left of the main one lives at negative x in both systems.
        let onExternal = CGRect(x: -1500, y: 200, width: 600, height: 400)
        let appKit = ScreenGeometry.flip(onExternal, referenceHeight: height)
        #expect(appKit.origin.x == -1500)
        #expect(appKit.origin.y == height - 200 - 400)
    }

    @Test("The pixel factor comes from the display the window mostly lies on")
    func picksDisplayWithLargestOverlap() {
        let builtIn = ScreenGeometry.Display(frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                             backingScale: 2)
        let external = ScreenGeometry.Display(frame: CGRect(x: 1470, y: 0, width: 1920, height: 1080),
                                              backingScale: 1)
        // 100 points on the built-in display, 500 on the external one.
        let straddling = CGRect(x: 1370, y: 100, width: 600, height: 300)
        #expect(ScreenGeometry.backingScale(for: straddling, displays: [builtIn, external], fallback: 2) == 1)

        let onBuiltIn = CGRect(x: 100, y: 100, width: 600, height: 300)
        #expect(ScreenGeometry.backingScale(for: onBuiltIn, displays: [builtIn, external], fallback: 1) == 2)
    }

    @Test("Without any overlap the fallback is used")
    func usesFallback() {
        let builtIn = ScreenGeometry.Display(frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                             backingScale: 2)
        let offscreen = CGRect(x: 5000, y: 5000, width: 10, height: 10)
        #expect(ScreenGeometry.backingScale(for: offscreen, displays: [builtIn], fallback: 3) == 3)
    }
}
