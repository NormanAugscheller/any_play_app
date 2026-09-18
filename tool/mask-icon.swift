// mask-icon.swift — turns full-bleed square artwork into a macOS app icon.
//
// macOS does not mask app icons itself. A full-bleed square shows up as a hard
// square tile next to the rounded icons of every other app, and recent macOS versions
// put icons that do not follow the template into a grey frame. This draws the artwork
// into Apple's icon grid: an 824 × 824 rounded square centred on a 1024 × 1024
// transparent canvas.
//
// Usage: swift tool/mask-icon.swift <input.png> <output.png>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = NSImage(contentsOfFile: arguments[1]),
      let cgSource = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: mask-icon <input.png> <output.png>\n".data(using: .utf8)!)
    exit(1)
}

let canvas: CGFloat = 1024
let body: CGFloat = 824
let cornerRadius: CGFloat = 185.4
let inset = (canvas - body) / 2

let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
let rect = CGRect(x: inset, y: inset, width: body, height: body)
context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
context.clip()
context.interpolationQuality = .high
context.draw(cgSource, in: rect)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL,
                                                        "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
