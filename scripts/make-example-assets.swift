// Draws the images used by the example skins in skills/playamp-skins/examples.
// Run: swift scripts/make-example-assets.swift
import AppKit

let root = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let walnut = root.appending(path: "skills/playamp-skins/examples/walnut")

func png(_ size: Int, _ name: String, draw: (CGContext, CGFloat) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: walnut.appending(path: name))
}

/// Seamless walnut grain: wavy lines with whole-number wave counts so the tile repeats cleanly.
func wood(_ g: CGContext, _ s: CGFloat, base: NSColor, dark: NSColor, light: NSColor) {
    g.setFillColor(base.cgColor); g.fill(CGRect(x: 0, y: 0, width: s, height: s))
    var seed: UInt64 = 7
    func random() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    for i in 0..<70 {
        let y0 = CGFloat(i) / 70 * s + random() * 4
        let amplitude = 1 + random() * 4, waves = CGFloat(Int(1 + random() * 3)), phase = random() * .pi * 2
        let color = (random() > 0.45 ? dark : light).withAlphaComponent(0.10 + random() * 0.22)
        g.setStrokeColor(color.cgColor); g.setLineWidth(0.6 + random() * 2.2)
        for offset in [-s, 0, s] {   // draw wrapped copies so lines continue across the tile edge
            g.beginPath()
            for x in stride(from: 0, through: s, by: 2) {
                let y = y0 + offset + amplitude * sin(x / s * waves * 2 * .pi + phase)
                x == 0 ? g.move(to: CGPoint(x: x, y: y)) : g.addLine(to: CGPoint(x: x, y: y))
            }
            g.strokePath()
        }
    }
}

try FileManager.default.createDirectory(at: walnut, withIntermediateDirectories: true)
try png(256, "wood.png") { g, s in
    wood(g, s, base: NSColor(red: 0.42, green: 0.26, blue: 0.14, alpha: 1), dark: NSColor(red: 0.18, green: 0.09, blue: 0.04, alpha: 1), light: NSColor(red: 0.70, green: 0.48, blue: 0.28, alpha: 1))
}
try png(256, "wood-dark.png") { g, s in
    wood(g, s, base: NSColor(red: 0.20, green: 0.12, blue: 0.07, alpha: 1), dark: NSColor(red: 0.06, green: 0.03, blue: 0.01, alpha: 1), light: NSColor(red: 0.42, green: 0.27, blue: 0.15, alpha: 1))
}
/// Record label: a sunburst (so the spin is easy to see) inside cream and gold rings, transparent outside.
try png(512, "label.png") { g, s in
    let c = CGPoint(x: s / 2, y: s / 2), r = s / 2
    g.addEllipse(in: CGRect(x: 0, y: 0, width: s, height: s)); g.clip()
    g.setFillColor(NSColor(red: 0.96, green: 0.90, blue: 0.76, alpha: 1).cgColor); g.fill(CGRect(x: 0, y: 0, width: s, height: s))
    for i in 0..<24 where i % 2 == 0 {
        let a0 = CGFloat(i) / 24 * 2 * .pi, a1 = CGFloat(i + 1) / 24 * 2 * .pi
        g.beginPath(); g.move(to: c); g.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: false); g.closePath()
        g.setFillColor(NSColor(red: 0.85, green: 0.42, blue: 0.16, alpha: 1).cgColor); g.fillPath()
    }
    for (radius, color) in [(r * 0.98, NSColor(red: 0.55, green: 0.18, blue: 0.10, alpha: 1)), (r * 0.90, .clear), (r * 0.36, NSColor(red: 0.96, green: 0.90, blue: 0.76, alpha: 1))] where color != .clear {
        g.setStrokeColor(color.cgColor); g.setLineWidth(radius == r * 0.98 ? s * 0.04 : s * 0.02)
        g.strokeEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
    }
    g.setFillColor(NSColor(red: 0.96, green: 0.90, blue: 0.76, alpha: 1).cgColor)
    g.fillEllipse(in: CGRect(x: c.x - r * 0.34, y: c.y - r * 0.34, width: r * 0.68, height: r * 0.68))
}
print("Wrote example images to \(walnut.path)")
