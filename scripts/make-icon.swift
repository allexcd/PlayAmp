// Draws the PlayAmp app icon (original artwork) and writes Config/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

let root = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let phosphor = NSColor(red: 0.5, green: 0.95, blue: 0.28, alpha: 1)

func draw(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // Body: brushed-metal rounded square on Apple's icon grid (824 pt, 100 pt margin).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set(); NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(white: 0.62, alpha: 1), NSColor(red: 0.29, green: 0.30, blue: 0.35, alpha: 1), NSColor(white: 0.13, alpha: 1)])!.draw(in: shape, angle: -70)
    NSColor(white: 1, alpha: 0.35).setStroke(); shape.lineWidth = 6; shape.stroke()

    // Title strip: grooved lines like the windows' chrome.
    for i in 0..<3 {
        let y = 812 - CGFloat(i) * 18
        NSColor(white: 0.08, alpha: 0.55).setFill(); NSRect(x: 190, y: y, width: 644, height: 6).fill()
        NSColor(white: 1, alpha: 0.25).setFill(); NSRect(x: 190, y: y - 4, width: 644, height: 3).fill()
    }

    // LCD.
    let lcd = NSRect(x: 180, y: 250, width: 664, height: 480)
    let lcdPath = NSBezierPath(roundedRect: lcd, xRadius: 36, yRadius: 36)
    NSColor(white: 0.03, alpha: 1).setFill(); lcdPath.fill()
    NSColor(white: 0.75, alpha: 0.6).setStroke(); lcdPath.lineWidth = 5; lcdPath.stroke()
    NSGraphicsContext.saveGraphicsState(); lcdPath.addClip()
    NSGradient(starting: phosphor.withAlphaComponent(0.16), ending: .clear)!.draw(in: lcd, angle: 90)

    // Spectrum bars with peak caps.
    let heights: [CGFloat] = [0.55, 0.82, 0.96, 0.74, 0.88, 0.62, 0.70, 0.48, 0.58, 0.36]
    let barWidth: CGFloat = 44, gap: CGFloat = 16
    let x0 = lcd.midX - (CGFloat(heights.count) * (barWidth + gap) - gap) / 2
    let floor = lcd.minY + 48, maxH = lcd.height - 120
    let barGradient = NSGradient(colors: [NSColor(red: 0.18, green: 0.62, blue: 0.16, alpha: 1), phosphor, NSColor(red: 1, green: 0.88, blue: 0.2, alpha: 1)])!
    for (i, h) in heights.enumerated() {
        let x = x0 + CGFloat(i) * (barWidth + gap)
        let height = (maxH * h / 22).rounded() * 22 // segmented like an LCD
        for segment in stride(from: CGFloat(0), to: height, by: 22) {
            let rect = NSRect(x: x, y: floor + segment, width: barWidth, height: 16)
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: rect).addClip()
            barGradient.draw(from: NSPoint(x: 0, y: floor), to: NSPoint(x: 0, y: floor + maxH), options: [])
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(white: 0.92, alpha: 1).setFill(); NSRect(x: x, y: floor + height + 14, width: barWidth, height: 8).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Transport row: play button.
    let button = NSRect(x: 412, y: 140, width: 200, height: 84)
    let buttonPath = NSBezierPath(roundedRect: button, xRadius: 18, yRadius: 18)
    NSGradient(starting: NSColor(white: 0.78, alpha: 1), ending: NSColor(red: 0.29, green: 0.30, blue: 0.35, alpha: 1))!.draw(in: buttonPath, angle: -90)
    NSColor.black.setStroke(); buttonPath.lineWidth = 5; buttonPath.stroke()
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 488, y: 156)); play.line(to: NSPoint(x: 488, y: 208)); play.line(to: NSPoint(x: 538, y: 182)); play.close()
    phosphor.setFill(); play.fill(); NSColor.black.setStroke(); play.lineWidth = 3; play.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try draw(CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
    }
}
try draw(1024).representation(using: .png, properties: [:])!.write(to: root.appending(path: "Config/AppIcon.png"))
let task = Process()
task.executableURL = URL(filePath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Config/AppIcon.icns").path]
try task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Config/AppIcon.icns" : "iconutil failed")
