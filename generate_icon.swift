#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Brand colour — matches the rest of the Jorvik suite (CopyLens, BrowserCommander, etc.).
let brandBlue = NSColor(red: 0x00/255.0, green: 0x40/255.0, blue: 0x80/255.0, alpha: 1.0)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let cx = s / 2
    let cy = s / 2

    // Background
    let bgRect = NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.18, yRadius: s * 0.18)
    brandBlue.setFill()
    bgPath.fill()

    let gradSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        NSColor(white: 1.0, alpha: 0.08).cgColor,
        NSColor(white: 0.0, alpha: 0.10).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: gradSpace, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(bgPath.cgPath)
        ctx.clip()
        ctx.drawRadialGradient(gradient,
            startCenter: CGPoint(x: cx, y: cy + s * 0.12),
            startRadius: 0,
            endCenter: CGPoint(x: cx, y: cy),
            endRadius: s * 0.55,
            options: [])
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(bgPath.cgPath)
    ctx.clip()

    // ── Source rectangle (small, lower-left) ──
    //
    // The "thing being magnified" — a small dashed-outline rectangle
    // sitting toward the lower-left of the icon. Filled with a faint
    // tint so it reads as content rather than just a frame.
    let srcW = s * 0.20
    let srcH = s * 0.14
    let srcX = s * 0.20
    let srcY = s * 0.20
    let srcRect = NSRect(x: srcX, y: srcY, width: srcW, height: srcH)
    let srcPath = NSBezierPath(roundedRect: srcRect, xRadius: s * 0.018, yRadius: s * 0.018)
    NSColor(white: 1.0, alpha: 0.14).setFill()
    srcPath.fill()
    srcPath.lineWidth = max(1.5, s * 0.015)
    let dash: [CGFloat] = [s * 0.030, s * 0.022]
    srcPath.setLineDash(dash, count: dash.count, phase: 0)
    NSColor(white: 1.0, alpha: 0.70).setStroke()
    srcPath.stroke()

    // ── Callout rectangle (large, upper-right) ──
    //
    // The zoomed view of the source. Solid white outline, faint tint
    // fill, with a couple of horizontal "content lines" inside to
    // suggest text/UI that's been magnified. Visibly larger than the
    // source to read as "this is the zoom-out result".
    let cW = s * 0.40
    let cH = s * 0.30
    let cX = s * 0.42
    let cY = s * 0.50
    let cRect = NSRect(x: cX, y: cY, width: cW, height: cH)
    let cPath = NSBezierPath(roundedRect: cRect, xRadius: s * 0.028, yRadius: s * 0.028)
    NSColor(white: 1.0, alpha: 0.18).setFill()
    cPath.fill()
    cPath.lineWidth = max(2.5, s * 0.028)
    cPath.setLineDash([], count: 0, phase: 0)
    NSColor.white.setStroke()
    cPath.stroke()

    // Two short content bars inside the callout for the "magnified
    // detail" feeling. Sized so they read as text-y on the smaller
    // iconset sizes too.
    let barH = max(2, s * 0.020)
    let barColor = NSColor(white: 1.0, alpha: 0.55)
    barColor.setFill()
    let bar1 = NSRect(x: cX + s * 0.05, y: cY + cH - s * 0.080 - barH,
                       width: cW - s * 0.10, height: barH)
    let bar2 = NSRect(x: cX + s * 0.05, y: cY + cH - s * 0.140 - barH,
                       width: cW * 0.65, height: barH)
    NSBezierPath(roundedRect: bar1, xRadius: barH/2, yRadius: barH/2).fill()
    NSBezierPath(roundedRect: bar2, xRadius: barH/2, yRadius: barH/2).fill()

    // ── Connector arrow ──
    //
    // High-contrast arrow from the source rectangle (top-right corner
    // area) up to the bottom-left of the callout. Two-layer stroke
    // (light pill behind a darker brand-blue line) so it reads cleanly
    // against both the navy bundle and the white callout outline.
    let tail = CGPoint(x: srcX + srcW * 0.85, y: srcY + srcH)
    let head = CGPoint(x: cX + s * 0.04, y: cY - s * 0.005)

    // Behind: thick light stroke for contrast
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.95).cgColor)
    ctx.setLineWidth(max(4, s * 0.045))
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: tail)
    ctx.addLine(to: head)
    ctx.strokePath()
    ctx.restoreGState()

    // Arrowhead — solid white triangle at the head end
    let arrowAngle = atan2(head.y - tail.y, head.x - tail.x)
    let arrowLen = s * 0.055
    let arrowSpread = CGFloat.pi / 6
    let aLeft  = CGPoint(x: head.x - cos(arrowAngle - arrowSpread) * arrowLen,
                         y: head.y - sin(arrowAngle - arrowSpread) * arrowLen)
    let aRight = CGPoint(x: head.x - cos(arrowAngle + arrowSpread) * arrowLen,
                         y: head.y - sin(arrowAngle + arrowSpread) * arrowLen)
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.beginPath()
    ctx.move(to: head)
    ctx.addLine(to: aLeft)
    ctx.addLine(to: aRight)
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

// Iconset emission

let outDir = "Resources/HawkEye.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let image = drawIcon(size: size)
    let tiff = image.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    let png = rep.representation(using: .png, properties: [:])!
    let path = "\(outDir)/icon_\(Int(size))x\(Int(size)).png"
    try? png.write(to: URL(fileURLWithPath: path))
    if size <= 512 {
        let bigImage = drawIcon(size: size * 2)
        let bigTiff = bigImage.tiffRepresentation!
        let bigRep = NSBitmapImageRep(data: bigTiff)!
        let bigPng = bigRep.representation(using: .png, properties: [:])!
        let path2x = "\(outDir)/icon_\(Int(size))x\(Int(size))@2x.png"
        try? bigPng.write(to: URL(fileURLWithPath: path2x))
    }
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", outDir, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print("→ Wrote Resources/AppIcon.icns")
