#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: make-icon.swift OUTPUT_DIRECTORY\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let manager = FileManager.default
try? manager.removeItem(at: iconset)
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)

let files: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func point(_ value: CGFloat, scale: CGFloat) -> CGFloat { value * scale }

func drawIcon(size: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(red: 0.075, green: 0.094, blue: 0.078, alpha: 1).setFill()
    NSBezierPath(roundedRect: canvas.insetBy(dx: point(28, scale: scale), dy: point(28, scale: scale)), xRadius: point(190, scale: scale), yRadius: point(190, scale: scale)).fill()

    let plateColors = [
        NSColor(red: 0.812, green: 0.760, blue: 0.538, alpha: 1),
        NSColor(red: 0.946, green: 0.936, blue: 0.891, alpha: 1),
        NSColor(red: 0.42, green: 0.49, blue: 0.40, alpha: 1)
    ]
    let offsets: [(CGFloat, CGFloat)] = [(0, 180), (70, 0), (0, -180)]

    for (index, offset) in offsets.enumerated() {
        let x = point(178 + offset.0, scale: scale)
        let y = point(398 + offset.1, scale: scale)
        let width = point(670, scale: scale)
        let height = point(155, scale: scale)
        let cut = point(62, scale: scale)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x + point(30, scale: scale), y: y))
        path.line(to: NSPoint(x: x + width - cut, y: y))
        path.line(to: NSPoint(x: x + width, y: y + cut))
        path.line(to: NSPoint(x: x + width, y: y + height - point(30, scale: scale)))
        path.curve(to: NSPoint(x: x + width - point(30, scale: scale), y: y + height), controlPoint1: NSPoint(x: x + width, y: y + height), controlPoint2: NSPoint(x: x + width, y: y + height))
        path.line(to: NSPoint(x: x + point(30, scale: scale), y: y + height))
        path.curve(to: NSPoint(x: x, y: y + height - point(30, scale: scale)), controlPoint1: NSPoint(x: x, y: y + height), controlPoint2: NSPoint(x: x, y: y + height))
        path.line(to: NSPoint(x: x, y: y + point(30, scale: scale)))
        path.curve(to: NSPoint(x: x + point(30, scale: scale), y: y), controlPoint1: NSPoint(x: x, y: y), controlPoint2: NSPoint(x: x, y: y))
        path.close()
        plateColors[index].setFill()
        path.fill()

        NSColor(red: 0.075, green: 0.094, blue: 0.078, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: x + point(46, scale: scale), y: y + point(46, scale: scale), width: point(62, scale: scale), height: point(62, scale: scale))).fill()
        NSBezierPath(roundedRect: NSRect(x: x + point(148, scale: scale), y: y + point(58, scale: scale), width: point(360, scale: scale), height: point(38, scale: scale)), xRadius: point(19, scale: scale), yRadius: point(19, scale: scale)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

for (name, size) in files {
    try drawIcon(size: size, to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
