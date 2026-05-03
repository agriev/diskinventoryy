#!/usr/bin/env swift
// Generates the placeholder AppIcon PNGs into Resources/Assets.xcassets/AppIcon.appiconset.
// Run from the repo root: swift Scripts/make-appicon.swift

import Foundation
import AppKit
import CoreGraphics

struct IconSpec {
    let pixels: Int
    let filename: String
}

let specs: [IconSpec] = [
    IconSpec(pixels: 16,   filename: "icon_16x16.png"),
    IconSpec(pixels: 32,   filename: "icon_16x16@2x.png"),
    IconSpec(pixels: 32,   filename: "icon_32x32.png"),
    IconSpec(pixels: 64,   filename: "icon_32x32@2x.png"),
    IconSpec(pixels: 128,  filename: "icon_128x128.png"),
    IconSpec(pixels: 256,  filename: "icon_128x128@2x.png"),
    IconSpec(pixels: 256,  filename: "icon_256x256.png"),
    IconSpec(pixels: 512,  filename: "icon_256x256@2x.png"),
    IconSpec(pixels: 512,  filename: "icon_512x512.png"),
    IconSpec(pixels: 1024, filename: "icon_512x512@2x.png"),
]

let outDir = URL(fileURLWithPath: "DiskInventoryY/Resources/Assets.xcassets/AppIcon.appiconset")

// A few cells, a stylized "Y" between the two largest.
let palette: [(NSColor, CGFloat)] = [
    (NSColor.systemTeal,    0.42),  // big top-left
    (NSColor.systemBlue,    0.30),  // big top-right
    (NSColor.systemPurple,  0.10),
    (NSColor.systemPink,    0.08),
    (NSColor.systemOrange,  0.05),
    (NSColor.systemYellow,  0.05),
]

func renderIcon(size: Int) -> Data {
    let canvas = CGSize(width: size, height: size)
    let scale = CGFloat(size)
    let radius = scale * 0.22

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Rounded background
    context.saveGState()
    context.beginPath()
    let bgRect = CGRect(origin: .zero, size: canvas).insetBy(dx: scale * 0.06, dy: scale * 0.06)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(bgPath)
    context.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor)
    context.fillPath()

    // Treemap-like cells inside the rounded card
    context.beginPath()
    context.addPath(bgPath)
    context.clip()

    let inner = bgRect.insetBy(dx: scale * 0.06, dy: scale * 0.06)
    var x = inner.minX
    var y = inner.minY
    let totalArea = inner.width * inner.height
    var remainingArea = totalArea
    var horizontalRowHeightLeft: CGFloat = inner.height

    for (index, (color, weight)) in palette.enumerated() {
        let area = totalArea * weight
        let isHorizontal = index % 2 == 0
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        if isHorizontal {
            cellHeight = inner.height * 0.5
            cellWidth = area / cellHeight
        } else {
            cellWidth = inner.width - (x - inner.minX)
            cellHeight = area / max(cellWidth, 1)
        }
        let rect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        // Cushion-ish gradient
        let highlight = CGGradient(
            colorsSpace: colorSpace,
            colors: [NSColor.white.withAlphaComponent(0.18).cgColor,
                     NSColor.black.withAlphaComponent(0.18).cgColor] as CFArray,
            locations: [0, 1]
        )!
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            highlight,
            start: rect.origin,
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
        context.restoreGState()

        if isHorizontal {
            x += cellWidth
            if x >= inner.maxX - 1 {
                x = inner.minX
                y += cellHeight
                horizontalRowHeightLeft -= cellHeight
            }
        } else {
            y += cellHeight
        }
        remainingArea -= area
    }

    // Big stylized "Y" cut out as negative space
    let font = NSFont.systemFont(ofSize: scale * 0.62, weight: .heavy)
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white.withAlphaComponent(0.9)
    ]
    let text = "Y" as NSString
    let textSize = text.size(withAttributes: textAttributes)
    let textRect = CGRect(
        x: (scale - textSize.width) / 2,
        y: (scale - textSize.height) / 2,
        width: textSize.width,
        height: textSize.height
    )

    // Draw via NSGraphicsContext to use string drawing
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    text.draw(in: textRect, withAttributes: textAttributes)
    NSGraphicsContext.restoreGraphicsState()

    context.restoreGState()

    guard let cgImage = context.makeImage() else {
        fatalError("Failed to render icon at \(size)px")
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to PNG-encode icon at \(size)px")
    }
    return pngData
}

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var seenSizes: Set<Int> = []
for spec in specs {
    let url = outDir.appendingPathComponent(spec.filename)
    let data: Data
    if seenSizes.contains(spec.pixels) {
        // Re-use already-rendered bytes for the matching pixel size
        let twin = specs.first { $0.pixels == spec.pixels && $0.filename != spec.filename }!
        data = try! Data(contentsOf: outDir.appendingPathComponent(twin.filename))
    } else {
        data = renderIcon(size: spec.pixels)
        seenSizes.insert(spec.pixels)
    }
    try! data.write(to: url)
    print("Wrote \(spec.filename) \(spec.pixels)x\(spec.pixels) — \(data.count) bytes")
}
