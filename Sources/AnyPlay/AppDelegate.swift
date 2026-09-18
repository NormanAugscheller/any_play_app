import AppKit
import AnyPlayKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?
    private var signalSources: [DispatchSourceSignal] = []
    private var handOverObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Menu.install()

        // Put back any window a previous run left behind — that run crashed before
        // it could clean up. Runs before anything else touches a window.
        CrashRecovery.restoreLeftovers(from: .standard)

        let controller = MainWindowController()
        mainWindow = controller
        controller.installStatusItem()

        // A second launch of AnyPlay asks this one to show its window.
        handOverObserver = SingleInstance.observeHandOver { [weak controller] in
            controller?.bringWindowForward()
        }

        // Show the window on the very first launch and while a permission is missing —
        // otherwise nobody would know where AnyPlay lives. After that it stays in the
        // menu bar until someone chooses "Choose Window …".
        let seenBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        if !seenBefore || !Permission.screenRecording.isGranted
            || LaunchOptions.current.hasAutoSelection {
            controller.bringWindowForward()
        }
        if LaunchOptions.current.opensSettings { controller.openSettings() }
        installSignalHandlers()

        if let seconds = LaunchOptions.current.quitAfter {
            let timer = Timer(timeInterval: seconds, repeats: false) { _ in
                NSApp.terminate(nil)
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// A foreign window must never be left displaced just because AnyPlay quit.
    /// That is exactly the kind of bug that works and quietly breaks something.
    func applicationWillTerminate(_ notification: Notification) {
        mainWindow?.restorePinnedWindows()
    }

    /// The same for a hard stop from outside. `applicationWillTerminate` does not run
    /// on SIGTERM; without this, a `pkill` or `killall` would leave the foreign window
    /// at overlay size. (A crash — SIGKILL, a segfault — cannot be caught at all; the
    /// placement journal covers that case at the next launch.)
    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            // Disable the default action, otherwise it fires before the source does.
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                // The source runs on the main queue, so this access is safe.
                MainActor.assumeIsolated {
                    self?.mainWindow?.restorePinnedWindows()
                }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// AnyPlay lives on in the menu bar when no window is open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// A minimal main menu. Without one, a hand-built app lacks even ⌘Q and ⌘W.
enum Menu {
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.tr("menu.about"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.tr("menu.hide"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L10n.tr("menu.quit"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.tr("menu.window"))
        windowMenu.addItem(withTitle: L10n.tr("menu.close"),
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
