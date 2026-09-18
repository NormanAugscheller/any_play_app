import Testing
@testable import AnyPlayKit

@Suite("Frame rate verdict")
struct FrameRateTests {

    @Test("Values measured during development land in the right class",
          arguments: [(0, FrameRateVerdict.idle),
                      (1, .stalled),      // window in a hidden fullscreen Space
                      (2, .stalled),
                      (3, .throttled),
                      (15, .throttled),   // fully covered by an opaque window
                      (19, .throttled),
                      (20, .healthy),
                      (57, .healthy)])    // visible window, 60 fps cap
    func classifies(fps: Int, expected: FrameRateVerdict) {
        #expect(FrameRateVerdict.classify(framesPerSecond: fps) == expected)
    }
}
