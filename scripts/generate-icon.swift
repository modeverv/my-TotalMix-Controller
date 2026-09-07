// Reproducible vector artwork, rendered separately at every macOS icon size.
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func render(_ pixels: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
    (transform as NSAffineTransform).concat()
    let body = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), 184)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0.07, 0.11, 0.14).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.14, 0.20, 0.23), ending: color(0.035, 0.065, 0.09))!
        .draw(in: body, angle: -90)
    color(0.5, 0.7, 0.73, 0.25).setStroke()
    body.lineWidth = 3
    body.stroke()
    // A tiny activity strip anchors the eight large snapshot pads.
    color(0.27, 0.91, 0.76).setFill()
    rounded(NSRect(x: 190, y: 785, width: 116, height: 12), 6).fill()
    for i in 0..<3 {
        color(0.43, 0.57, 0.59, 0.55).setFill()
        NSBezierPath(ovalIn: NSRect(x: 766 + i * 24, y: 785, width: 12, height: 12)).fill()
    }
    for row in 0..<2 {
        for column in 0..<4 {
            let selected = row == 0 && column == 0
            let rect = NSRect(x: 188 + column * 168, y: row == 0 ? 506 : 270, width: 144, height: 204)
            let pad = rounded(rect, 30)
            if selected {
                NSGradient(starting: color(0.48, 1, 0.83), ending: color(0.12, 0.70, 0.59))!
                    .draw(in: pad, angle: -90)
                color(0.65, 1, 0.90, 0.8).setStroke()
            } else {
                NSGradient(starting: color(0.26, 0.34, 0.38), ending: color(0.15, 0.22, 0.26))!
                    .draw(in: pad, angle: -90)
                color(0.54, 0.70, 0.73, 0.22).setStroke()
            }
            pad.lineWidth = 3
            pad.stroke()
            color(selected ? 0.04 : 0.55, selected ? 0.32 : 0.70, selected ? 0.28 : 0.73, selected ? 0.7 : 0.45).setFill()
            rounded(NSRect(x: rect.minX + 29, y: rect.minY + 29, width: 44, height: 8), 4).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
for size in [16, 32, 128, 256, 512] {
    try render(size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(512, to: root.appendingPathComponent("Resources/AppIcon-preview.png"))
