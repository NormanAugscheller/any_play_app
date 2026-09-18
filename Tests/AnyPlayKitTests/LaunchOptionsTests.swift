import Testing
import CoreGraphics
@testable import AnyPlayKit

@Suite("Launch options")
struct LaunchOptionsTests {

    @Test("Every switch is recognised")
    func parsesAllSwitches() {
        let options = LaunchOptions(["AnyPlay", "--select", "com.apple.Safari", "--select-title", "YouTube",
                                     "--overlay", "--no-pin", "--log", "/tmp/x.log", "--quit-after", "30",
                                     "--selftest-input", "--open-settings"])
        #expect(options.selectBundleID == "com.apple.Safari")
        #expect(options.selectTitleContains == "YouTube")
        #expect(options.showOverlayImmediately)
        #expect(!options.placesTargetWindow)
        #expect(options.logPath == "/tmp/x.log")
        #expect(options.quitAfter == 30)
        #expect(options.runsInputSelftest)
        #expect(options.opensSettings)
    }

    @Test("Without switches everything is off and windows are placed")
    func defaults() {
        let options = LaunchOptions(["AnyPlay"])
        #expect(!options.hasAutoSelection)
        #expect(options.placesTargetWindow)
        #expect(options.quitAfter == nil)
    }

    @Test("Unknown arguments, such as those macOS adds, are ignored")
    func ignoresUnknown() {
        let options = LaunchOptions(["AnyPlay", "-AppleLanguages", "(de)", "--overlay"])
        #expect(options.showOverlayImmediately)
    }

    @Test("--select picks the largest matching window, --select-title narrows it down")
    func matchesWindows() {
        func window(_ id: CGWindowID, _ title: String, _ width: CGFloat) -> TargetWindow {
            TargetWindow(windowID: id, processID: 1, bundleID: "com.apple.Safari", appName: "Safari",
                         title: title, frame: CGRect(x: 0, y: 0, width: width, height: 500), isOnScreen: true)
        }
        let windows = [window(1, "Mail", 1200), window(2, "YouTube – Video", 800)]
        #expect(LaunchOptions(["x", "--select", "com.apple.Safari"]).match(in: windows)?.windowID == 1)
        #expect(LaunchOptions(["x", "--select", "com.apple.Safari", "--select-title", "youtube"])
                    .match(in: windows)?.windowID == 2)
        #expect(LaunchOptions(["x", "--select", "com.other"]).match(in: windows) == nil)
    }
}
