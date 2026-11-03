#!/usr/bin/env swift
// Renders the Pointwise app icon into Pointwise/Resources/Assets.xcassets/AppIcon.appiconset
// and docs/images/icon.png. Usage, from the repository root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func renderIcon() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824 pt body centered on a 1024 canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(
        starting: NSColor(srgbRed: 0.20, green: 0.62, blue: 1.00, alpha: 1),
        ending: NSColor(srgbRed: 0.24, green: 0.20, blue: 0.78, alpha: 1)
    )!.draw(in: shape, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    drawCurve()
    NSGraphicsContext.restoreGraphicsState()
    drawMouse(center: NSPoint(x: 560, y: 440))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// An acceleration curve: flat for slow movement, then rising.
func drawCurve() {
    let curve = NSBezierPath()
    curve.move(to: NSPoint(x: 150, y: 250))
    curve.curve(to: NSPoint(x: 880, y: 840), controlPoint1: NSPoint(x: 560, y: 250), controlPoint2: NSPoint(x: 700, y: 520))
    curve.lineWidth = 54
    curve.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.28).setStroke()
    curve.stroke()
}

func drawMouse(center: NSPoint) {
    let size = NSSize(width: 330, height: 470)
    let rect = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    let mouse = NSBezierPath(roundedRect: rect, xRadius: size.width / 2, yRadius: size.width / 2)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.08, green: 0.05, blue: 0.35, alpha: 0.5)
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.shadowBlurRadius = 34
    shadow.set()
    NSColor.white.setFill()
    mouse.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Button split and scroll wheel.
    let ink = NSColor(srgbRed: 0.26, green: 0.30, blue: 0.82, alpha: 1)
    let split = NSBezierPath()
    split.move(to: NSPoint(x: center.x, y: rect.maxY - 8))
    split.line(to: NSPoint(x: center.x, y: rect.maxY - 150))
    split.lineWidth = 10
    split.lineCapStyle = .round
    ink.withAlphaComponent(0.25).setStroke()
    split.stroke()

    let wheel = NSBezierPath(roundedRect: NSRect(x: center.x - 24, y: rect.maxY - 190, width: 48, height: 96), xRadius: 24, yRadius: 24)
    ink.setFill()
    wheel.fill()
}

let output = URL(fileURLWithPath: "Pointwise/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let master = renderIcon()
let entries: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []

for entry in entries {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    let scaled = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try scaled.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(entry.points)x\(entry.points)", "scale": "\(entry.scale)x", "filename": name])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")

let preview = URL(fileURLWithPath: "docs/images/icon.png")
try FileManager.default.createDirectory(at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)
try master.representation(using: .png, properties: [:])!.write(to: preview)
print("Wrote \(preview.path)")
