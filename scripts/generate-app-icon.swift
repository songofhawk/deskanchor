#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? ".build/DeskAnchor.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("DeskAnchor.iconset")

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let sizes: [(filename: String, pixels: CGFloat, points: CGFloat)] = [
    ("icon_16x16.png", 16, 16),
    ("icon_16x16@2x.png", 32, 16),
    ("icon_32x32.png", 32, 32),
    ("icon_32x32@2x.png", 64, 32),
    ("icon_128x128.png", 128, 128),
    ("icon_128x128@2x.png", 256, 128),
    ("icon_256x256.png", 256, 256),
    ("icon_256x256@2x.png", 512, 256),
    ("icon_512x512.png", 512, 512),
    ("icon_512x512@2x.png", 1024, 512)
]

for (filename, pixels, points) in sizes {
    let image = renderIcon(size: pixels)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        throw IconError.exportFailed(filename)
    }
    bitmap.size = NSSize(width: points, height: points)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.exportFailed(filename)
    }
    try png.write(to: iconsetURL.appendingPathComponent(filename))
}

try writeICNS(to: outputURL)
try? fileManager.removeItem(at: iconsetURL)

enum IconError: Error {
    case exportFailed(String)
    case invalidIconType(String)
}

func writeICNS(to url: URL) throws {
    let elements: [(type: String, pixels: CGFloat)] = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024)
    ]

    var body = Data()
    for element in elements {
        let png = try pngData(size: element.pixels)
        guard let typeData = element.type.data(using: .ascii), typeData.count == 4 else {
            throw IconError.invalidIconType(element.type)
        }
        body.append(typeData)
        appendBigEndianUInt32(UInt32(png.count + 8), to: &body)
        body.append(png)
    }

    var icns = Data("icns".utf8)
    appendBigEndianUInt32(UInt32(body.count + 8), to: &icns)
    icns.append(body)
    try icns.write(to: url)
}

func pngData(size: CGFloat) throws -> Data {
    let image = renderIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.exportFailed("\(Int(size))px")
    }
    return png
}

func appendBigEndianUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let path = NSBezierPath(
        roundedRect: rect,
        xRadius: size * 0.25,
        yRadius: size * 0.25
    )

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.35, green: 0.38, blue: 1.0, alpha: 1.0)
    ])
    gradient?.draw(in: rect, angle: 315)
    NSGraphicsContext.restoreGraphicsState()

    drawWindows(in: rect.insetBy(dx: size * 0.22, dy: size * 0.25))

    image.unlockFocus()
    return image
}

func drawWindows(in rect: NSRect) {
    NSColor.white.set()
    let lineWidth = max(2, rect.width * 0.08)

    let back = NSBezierPath(roundedRect: NSRect(
        x: rect.minX,
        y: rect.midY - rect.height * 0.18,
        width: rect.width * 0.56,
        height: rect.height * 0.48
    ), xRadius: lineWidth, yRadius: lineWidth)
    back.lineWidth = lineWidth
    back.stroke()

    let frontRect = NSRect(
        x: rect.minX + rect.width * 0.34,
        y: rect.minY,
        width: rect.width * 0.66,
        height: rect.height * 0.58
    )
    let front = NSBezierPath(roundedRect: frontRect, xRadius: lineWidth, yRadius: lineWidth)
    front.lineWidth = lineWidth
    front.stroke()

    let dotRadius = lineWidth * 0.42
    let dotY = frontRect.maxY - lineWidth * 1.55
    for offset in [0.50, 0.64, 0.78] {
        let centerX = frontRect.minX + frontRect.width * offset
        NSBezierPath(ovalIn: NSRect(
            x: centerX - dotRadius,
            y: dotY - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )).fill()
    }
}
