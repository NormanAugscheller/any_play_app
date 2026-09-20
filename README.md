<p align="center">
  <img src="Resources/Icon/AppIcon-256.png" width="128" height="128" alt="AnyPlay icon">
</p>

# AnyPlay

Picture-in-picture for any window on macOS. AnyPlay mirrors a window of another
app — Safari playing a video, for example — into a small panel that stays on top of
everything, **including a game running fullscreen**.

What sets it apart from an "always on top" window: macOS has no public way to change
the window level of **another** app. So AnyPlay mirrors the window's content with
ScreenCaptureKit into a panel of its own, and places the real window pixel-exactly
beneath it.

## Requirements

- macOS 14 or later (developed and measured on macOS 26.6, Apple Silicon)
- Xcode or just the Command Line Tools — nothing else, there are no dependencies

## Build and run

```bash
git clone https://github.com/NormanAugscheller/any_play_app.git
cd any_play_app
./run.sh
```

That is all. `run.sh` builds with the Swift Package Manager, assembles
`build/AnyPlay.app`, signs it and starts it. `./build.sh` only builds, `./test.sh`
runs the tests.

Two things are deliberate:

- **The built app always lives at the same path** (`build/AnyPlay.app`) with the same
  bundle ID, and is signed with your Apple Development certificate if you have one.
  macOS ties the permissions to that identity. With an ad-hoc signature it would
  remember a hash of the binary instead, which changes with every build — and ask for
  the permissions again each time.
- **The app is started with `open`, not directly.** Only then is the app itself the
  responsible process for the permissions. Started from a terminal, they would be
  attributed to the terminal.

If the Xcode toolchain is unusable (after an update, Xcode's license has to be accepted
again), the scripts fall back to the Command Line Tools on their own.

## Permissions

AnyPlay needs two permissions under **System Settings → Privacy & Security**:

| Permission | Used for | Without it |
|---|---|---|
| **Screen Recording** | mirroring the chosen window | no picture — AnyPlay explains what is missing instead of showing black |
| **Accessibility** | placing the real window beneath the overlay, sending commands, switching focus | the overlay only mirrors and moves nothing |

On first launch AnyPlay leads you there. Screen Recording only takes effect after a
restart of the app; AnyPlay offers to restart itself.

AnyPlay runs **without the App Sandbox**. There is no way around that: the sandbox does
not allow the Accessibility API on other processes.

## Using it

AnyPlay lives in the menu bar and has no Dock icon. Every launch opens its window, and
only one AnyPlay runs at a time — launching it again brings the running one's window
forward.

**To quit**, use the button at the bottom of the window list, or the menu bar icon →
*Quit AnyPlay*. Closing the window is not the same thing: AnyPlay stays in the menu bar
so the overlay survives. Either way a pinned window gets its old size back first.

If the menu bar icon is nowhere to be seen, a menu bar manager such as Ice, Bartender or
Hidden Bar is probably hiding it — that is also why the window carries a quit button of
its own.

| Shortcut | Action |
|---|---|
| ⌃⌥⌘P | show / hide the overlay |
| ⌃⌥⌘I | switch between passive and input mode |
| ⌃⌥⌘K | send play / pause to the target window |

All three can be changed in Settings.

**Passive mode** — the game keeps focus. The overlay shows; control happens through
commands that are delivered to the target app as key presses.

**Input mode** — the target app is really activated. Its real window lies exactly
beneath the overlay, so you can type and click normally. The shortcut brings focus back.

Drag the overlay anywhere to move it, drag its edges to resize it; the aspect ratio is
kept. To close it, use the button in its top right corner (appears on hover) or Escape.

The interface follows the system language — English and German are included.

## Known limits

All of these were measured, not assumed. [FEASIBILITY.md](FEASIBILITY.md) has the numbers.

- **Mouse clicks and scrolling cannot be forwarded to a window in the background.**
  `CGEventPostToPid` does not deliver mouse events to Safari — zero out of ten attempts
  across six runs, not even while Safari was active. Key presses arrive reliably. That
  is why passive mode has commands, not a mouse.
- **A web page's own shortcuts need the page to have keyboard focus.** ⌘T sent to
  Safari works at once; YouTube's K for play/pause only when the page has focus. The
  difference is who receives it: the application or the page.
- **Some kinds of fullscreen throttle the source.** With two games tested, the stream
  kept running at a full 57–59 frames per second. An **app** in a native fullscreen
  Space, however, dropped the source to 1 frame per second. AnyPlay shows the measured
  frame rate and warns instead of passing on a slideshow.
- **The target has to be on the current Space when pinning.** The Accessibility API only
  sees windows on the current Space. A window behind a fullscreen app can be mirrored
  but not placed; AnyPlay says so and asks you to switch there.
- **The target app decides its minimum size.** Safari does not get narrower than 574
  points. AnyPlay then adapts the overlay rather than lying next to it.
- **The overlay must not be fully opaque.** An opaque window on top of the target drops
  the target's frame rate from 57 to 15, because macOS then treats it as covered. The
  panel therefore runs at `alphaValue = 0.99`.
- **Several monitors: reasoned and unit-tested, not tried on hardware.** Coordinate
  conversion always uses the display that holds the origin of the global coordinate
  space, and the stream resolution follows the pixel factor of the display the target
  window is on. It has only ever run on a single built-in display.

## When something goes wrong

AnyPlay puts a pinned window back when it quits — normally, via ⌘Q, and on `SIGTERM`.
A crash skips all of that, so the original size of a pinned window is written to
`~/Library/Application Support/AnyPlay/placements.json` the moment it is pinned. At the
next launch AnyPlay puts back every window that still sits exactly where it was left.
A window you have moved since is left alone.

## Structure

```
Sources/AnyPlayKit/          logic that can be tested without a window server
  ScreenGeometry, WindowFilter, Rediscovery, Shortcut, PlacementJournal, …
Sources/AnyPlay/             the app
  main.swift, AppDelegate    start-up, single instance, menu, clean-up on quit
  CrashRecovery              puts back windows a crashed run left behind
  PinSession, WindowWatcher  one pinned window; minimized, found again, closed
  Capture/                   ScreenCaptureKit, IOSurface straight to CALayer
  Overlay/                   the panel on top of everything
  Accessibility/             moving other apps' windows and putting them back
  Input/                     key forwarding and global shortcuts
  UI/                        main window, settings, menu bar
Resources/                   Info.plist, translations, icon
Tests/AnyPlayKitTests/       unit tests (swift-testing)
tool/                        icon and release scripts
```

`LaunchOptions` and `DiagnosticLog` exist for development and automated testing (for
example `--select com.apple.Safari --overlay --log /tmp/anyplay.log`); normal use does
not need them.

## Tests

```bash
./test.sh
```

39 tests cover the parts that went wrong at least once during development: coordinate
conversion across displays, which windows are offered, finding a window again without
ever taking the one behind it, the crash journal, stored shortcuts, the frame-rate
verdict, and whether every piece of interface text exists in every language.

With only the Command Line Tools installed, `swift test` does not find the testing
framework on its own; `test.sh` passes the paths.

## Icon

The icon is built from `Resources/Icon/AppIcon-source.png`, a full-bleed 1024 × 1024
image. `tool/make-icon.sh` fits it into the macOS icon grid (an 824-point rounded
square with transparent margins) and produces `AppIcon.icns`.

## Distribution and Gatekeeper

`tool/release.sh` builds a zip in `dist/`. **That archive is not notarized.** It is
signed with an Apple Development certificate, which is not meant for distribution: on
another Mac, Gatekeeper refuses to open it.

Proper distribution needs a **Developer ID** certificate and **notarization** by Apple,
both of which require a paid Apple Developer Program membership. Until then, the honest
way is to **build it yourself** with `./run.sh`. If you still want to use a downloaded
archive, you have to remove the quarantine flag yourself, knowing what that means:

```bash
xattr -dr com.apple.quarantine /path/to/AnyPlay.app
```

After moving the app to another location, the permissions have to be granted again.

## License

MIT, see [LICENSE](LICENSE).
