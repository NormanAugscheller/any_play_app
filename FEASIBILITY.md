# Feasibility

Before any real app existed, small throwaway prototypes answered one question: does the
idea hold up? Mirror another app's window with ScreenCaptureKit, show it in a panel on
top of a fullscreen game, and control it from there.

Every prototype wrote a log or took its own screenshot and evaluated it itself —
results about fullscreen, focus and visibility were measured, never assumed.

**Setup:** MacBook Air M5, macOS 26.6.2, a 1470 × 956 point display at 2× (2940 × 1912
pixels), Safari 26 playing a YouTube video, Steam with Geometry Dash and Bills Must Be
Paid.

## Summary

| Question | Answer |
|---|---|
| Does Safari keep drawing while a fullscreen game covers it? | **Yes, at full speed** — two games, about two minutes each, 57–59 changed frames per second |
| Does an overlay panel appear above a fullscreen game? | **Yes** — above both games and above an app in native fullscreen |
| Can another app's window be resized and put back exactly? | **Yes** — if it is done in two passes |
| Do mouse clicks and scrolls reach Safari in the background? | **No.** Key presses do |
| Does a global shortcut fire while a game runs fullscreen? | **Yes** — eight out of eight presses |

## 1. Does the source keep drawing while covered?

ScreenCaptureKit is change-driven: a missing frame means "nothing changed", not
"error". So each frame was checked for status `complete` **and** changed pixel content,
and once per second the log recorded which app was in front and whether the target
window was on screen — so the phases were visible in the log itself.

| Situation | Frames with changed content |
|---|---|
| Safari visible | 57–58 per second |
| Geometry Dash fullscreen, Safari not on the visible Space | 57–59 per second, for 120 s |
| Bills Must Be Paid fullscreen, Safari not on the visible Space | 57–59 per second, for 137 s |
| Finder in native fullscreen, Safari not on the visible Space | **1 per second** |
| An opaque panel exactly on top of the Safari window | **15 per second** |
| The same panel at alpha 0.99 | 57 per second |

In the main use case — a real game in fullscreen — the stream does not dry up. The idea
holds.

Two findings shaped the app. First, an **app** in a native fullscreen Space made Safari
drop to 1 frame per second while neither game did; the likely reason is that a native
fullscreen Space marks the covered windows as invisible and the app then throttles
itself. Second, and more important: an overlay that is fully **opaque** throttles the
very window it mirrors, from 57 to 15 frames per second, because macOS counts only fully
opaque windows as covering. At `alphaValue = 0.99` the source keeps its full rate with
an identical-looking picture.

## 2. Does the overlay appear above a fullscreen game?

The test panel was pure magenta with a running seconds counter. The prototype took its
own screenshots and **counted the magenta pixels**; the image only served as a second
check.

It appeared in every case — 10.54–10.55 % magenta with the same bounding box in each of
eight screenshots over two games, and above an app in native fullscreen. The counter in
the screenshots proves the panel was alive at that moment.

Needed: `.nonactivatingPanel`, level `.screenSaver`, collection behaviour
`.canJoinAllSpaces` and `.stationary`. One trap cost two measurements: setting
`isFloatingPanel = true` resets the level to `.floating` (3) and silently overwrites a
level set before it.

## 3. Moving another app's window and putting it back

Works exactly, with two lessons:

- **One pass is not enough.** macOS limits a window's height to the visible area below
  its current position. When restoring, the window first came back as 1300 × **322**
  instead of 1300 × 727, although both set calls reported success. Setting position and
  size twice fixes it — and the result has to be read back; the return value is not to
  be trusted.
- **Safari's minimum width is 574 points.** A 500-point request is silently rounded up.

## 4. Forwarding clicks, scrolls and keys

Measured by picture content: two captures 1.2 s apart, counting the share of pixels
that changed — a playing video 6–37 %, a paused one 0.00 %. What counted was a **change
of state** (playing ↔ paused), with two controls: the same click sent the normal way,
and the same click while Safari was active.

| Path | Result |
|---|---|
| Mouse click via `CGEventPostToPid`, Safari in the background | no effect (0 of 2) |
| Mouse click via `CGEventPostToPid`, Safari active | no effect (0 of 2) |
| Scroll via `CGEventPostToPid` | no effect |
| **Key press** via `CGEventPostToPid`, Safari in the background | **works** (9.37 % → 0.00 %) |
| A normal click at the same spot | works (5.90 % → 0.00 %) |

Across six runs, not a single mouse click delivered this way had any effect. The normal
click at the same spot works, and key presses arrive — only mouse events do not. That
ruled out the originally planned passive mode with a mouse. AnyPlay sends commands as
key presses instead, and switches to input mode for anything that needs a mouse.

## 5. Global shortcuts in a fullscreen game

`RegisterEventHotKey` rather than an event monitor, because a registered hotkey swallows
the event and the game does not receive it too. Eight shortcut presses during two
fullscreen games, eight triggered, each time with the game as the frontmost app in the
same log line.

One caveat: the presses were posted synthetically through the same path a real keyboard
uses. A game that reads the keyboard raw through IOHIDManager could react differently
to a synthetic event than to a real one.

## Verdict

The idea holds. Three consequences went into the app: the overlay runs at alpha 0.99,
passive mode uses key commands instead of the mouse, and the app watches its own frame
rate so a throttled source is named rather than shown as a stuttering picture.
