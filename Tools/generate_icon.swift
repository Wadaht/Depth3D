#!/usr/bin/env swift

//
// generate_icon.swift
// Run on macOS:  swift Tools/generate_icon.swift
//
// Produces Depth3D/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// at 1024×1024 with a clean LiDAR-cube design.
//

import Cocoa
import CoreGraphics
import Foundation

// MARK: - Configuration

let size: CGFloat = 1024
let outputPath = "Depth3D/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

// MARK: - Drawing

let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    print("error: no graphics context")
    exit(1)
}

// Background gradient (deep blue → violet, top-right → bottom-left)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bgGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.06, green: 0.04, blue: 0.22, alpha: 1.0),
        CGColor(srgbRed: 0.20, green: 0.08, blue: 0.38, alpha: 1.0),
        CGColor(srgbRed: 0.10, green: 0.20, blue: 0.55, alpha: 1.0)
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: size, y: size),
    end: CGPoint(x: 0, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// Subtle radial highlight from center
let highlight = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.6, green: 0.7, blue: 1.0, alpha: 0.18),
        CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    highlight,
    startCenter: CGPoint(x: size * 0.5, y: size * 0.55),
    startRadius: 0,
    endCenter: CGPoint(x: size * 0.5, y: size * 0.55),
    endRadius: size * 0.65,
    options: []
)

// Isometric cube wireframe — cyan with glow
let cx = size / 2
let cy = size / 2
let scale = size * 0.30
let dx = scale * cos(.pi / 6)   // 30°
let dy = scale * sin(.pi / 6)

// Eight cube corners in isometric projection
// Front face is the lower-left rhombus from the viewer
let v_botFront  = CGPoint(x: cx,        y: cy - scale * 0.95)
let v_botRight  = CGPoint(x: cx + dx,   y: cy - scale * 0.95 + dy)
let v_botBack   = CGPoint(x: cx,        y: cy - scale * 0.95 + 2 * dy)
let v_botLeft   = CGPoint(x: cx - dx,   y: cy - scale * 0.95 + dy)
let v_topFront  = CGPoint(x: cx,        y: cy + scale * 0.05)
let v_topRight  = CGPoint(x: cx + dx,   y: cy + scale * 0.05 + dy)
let v_topBack   = CGPoint(x: cx,        y: cy + scale * 0.05 + 2 * dy)
let v_topLeft   = CGPoint(x: cx - dx,   y: cy + scale * 0.05 + dy)

func strokeFace(_ ctx: CGContext, _ pts: [CGPoint], width: CGFloat, color: CGColor, fill: CGColor? = nil) {
    ctx.beginPath()
    ctx.move(to: pts[0])
    for p in pts.dropFirst() { ctx.addLine(to: p) }
    ctx.closePath()
    if let fill = fill {
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    ctx.beginPath()
    ctx.move(to: pts[0])
    for p in pts.dropFirst() { ctx.addLine(to: p) }
    ctx.closePath()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

// Soft fill for top face to give 3D feel
let cyan = CGColor(srgbRed: 0.35, green: 0.85, blue: 1.0, alpha: 1.0)
let cyanFillTop = CGColor(srgbRed: 0.35, green: 0.85, blue: 1.0, alpha: 0.18)
let cyanFillRight = CGColor(srgbRed: 0.35, green: 0.85, blue: 1.0, alpha: 0.10)
let cyanFillFront = CGColor(srgbRed: 0.35, green: 0.85, blue: 1.0, alpha: 0.06)

ctx.setShadow(offset: .zero, blur: 32, color: cyan)

// Front (left-facing) face
strokeFace(ctx,
    [v_botLeft, v_botFront, v_topFront, v_topLeft],
    width: 22, color: cyan, fill: cyanFillFront)

// Right (right-facing) face
strokeFace(ctx,
    [v_botFront, v_botRight, v_topRight, v_topFront],
    width: 22, color: cyan, fill: cyanFillRight)

// Top face
strokeFace(ctx,
    [v_topLeft, v_topFront, v_topRight, v_topBack],
    width: 22, color: cyan, fill: cyanFillTop)

// LiDAR scan dots — small bright points on the front face
ctx.setShadow(offset: .zero, blur: 0, color: nil)
let dotCount = 6
for i in 0..<dotCount {
    let t = CGFloat(i) / CGFloat(dotCount - 1)
    let p = CGPoint(
        x: v_botFront.x + (v_topRight.x - v_botFront.x) * t,
        y: v_botFront.y + (v_topRight.y - v_botFront.y) * t
    )
    let dot = CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.fillEllipse(in: dot)
}

canvas.unlockFocus()

// MARK: - Save as PNG

guard let tiffData = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("error: failed to encode PNG")
    exit(1)
}

let outURL = URL(fileURLWithPath: outputPath)
do {
    try FileManager.default.createDirectory(
        at: outURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outURL)
    print("✓ wrote \(outputPath)  (\(pngData.count / 1024) KB)")
} catch {
    print("error: \(error)")
    exit(1)
}
