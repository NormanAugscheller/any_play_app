// main.swift — entry point.
//
// No @main attribute: AnyPlay needs an NSApplication whose activation policy and
// windows it controls itself.

import AppKit

// Only one AnyPlay at a time. A second launch hands over to the running instance
// (which brings its window forward) and quits before it creates anything.
if SingleInstance.handOverIfAlreadyRunning() {
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// A menu bar app without a Dock icon. For a tool that runs next to a fullscreen
// game, a Dock icon only gets in the way — and clicking it would pull focus away.
application.setActivationPolicy(.accessory)
application.run()
