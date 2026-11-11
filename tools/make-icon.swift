// Generates AppIcon.icns for Closed-Lid Mode.
//
// Drawn from scratch with Core Graphics - deliberately NOT an SF Symbol,
// because Apple's SF Symbols licence does not permit using them as app icons.
//
//   swift tools/make-icon.swift            (writes build/AppIcon.icns)

import AppKit

func drawIcon(size: CGFloat, into ctx: CGContext) {
    let s = size

    // Rounded-square background with a vertical gradient.
    let radius = s * 0.2237
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()
    let colors = [
        CGColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1),
        CGColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1)
    ] as CFArray
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
    }
    ctx.restoreGState()

    // Closed laptop, seen head on: a wide rounded bar with a seam across it.
    let bodyW = s * 0.60
    let bodyH = s * 0.34
    let bodyX = (s - bodyW) / 2
    let bodyY = s * 0.34
    let bodyRadius = s * 0.055
    let body = CGPath(roundedRect: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
                      cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)
    ctx.setLineWidth(s * 0.042)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addPath(body)
    ctx.strokePath()

    // The seam where the lid meets the base - this is what says "shut".
    ctx.setLineWidth(s * 0.030)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.move(to: CGPoint(x: bodyX + s * 0.055, y: bodyY + bodyH * 0.46))
    ctx.addLine(to: CGPoint(x: bodyX + bodyW - s * 0.055, y: bodyY + bodyH * 0.46))
    ctx.strokePath()

    // Foot, so it reads as a laptop on a desk rather than a plain box.
    ctx.setLineWidth(s * 0.034)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
    ctx.move(to: CGPoint(x: bodyX - s * 0.045, y: bodyY - s * 0.055))
    ctx.addLine(to: CGPoint(x: bodyX + bodyW + s * 0.045, y: bodyY - s * 0.055))
    ctx.strokePath()

    // The "staying awake" dot, matching the green menu bar state.
    let dotR = s * 0.097
    let dotC = CGPoint(x: s * 0.735, y: s * 0.715)
    ctx.setFillColor(CGColor(red: 0.18, green: 0.80, blue: 0.35, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2))
    ctx.setStrokeColor(CGColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1))
    ctx.setLineWidth(s * 0.030)
    ctx.strokeEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2))
}

func png(size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    drawIcon(size: CGFloat(size), into: ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let root = FileManager.default.currentDirectoryPath
let iconset = "\(root)/build/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// The filenames iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, px) in variants {
    guard let data = png(size: px) else { fatalError("could not render \(name)") }
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("wrote \(variants.count) sizes to \(iconset)")
