#!/usr/bin/env swift

// Renders the Brick app icon to a 1024×1024 PNG and drops it into the
// AppIcon.appiconset. Run from the repo root:
//
//   swift Tools/render-app-icon.swift
//
// Mirrors `Brick/Views/AppIconPreview.swift` exactly. Update both if the
// design ever changes. The double-source is deliberate so the in-Xcode
// preview and the rasteriser never silently diverge.

import AppKit
import SwiftUI

@MainActor
struct AppIconMark: View {
    var size: CGFloat = 1024

    private var cream: Color { Color(red: 0.964, green: 0.933, blue: 0.886) }
    private var clay: Color { Color(red: 0.722, green: 0.361, blue: 0.220) }
    private var clayDeep: Color { Color(red: 0.612, green: 0.286, blue: 0.149) }

    var body: some View {
        ZStack {
            Rectangle().fill(cream)
            let unit = size / 12
            let brickW = unit * 3
            let brickH = unit * 1.6
            let brickRadius = unit * 0.32
            let rowGap = unit * 0.45
            let colGap = unit * 0.4

            VStack(spacing: rowGap) {
                HStack(spacing: colGap) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: brickRadius, style: .continuous)
                            .fill(clay)
                            .frame(width: brickW, height: brickH)
                    }
                }
                HStack(spacing: colGap) {
                    RoundedRectangle(cornerRadius: brickRadius, style: .continuous)
                        .fill(clayDeep)
                        .frame(width: brickW / 2 - colGap / 2, height: brickH)
                    RoundedRectangle(cornerRadius: brickRadius, style: .continuous)
                        .fill(clayDeep)
                        .frame(width: brickW, height: brickH)
                    RoundedRectangle(cornerRadius: brickRadius, style: .continuous)
                        .fill(clayDeep)
                        .frame(width: brickW, height: brickH)
                    RoundedRectangle(cornerRadius: brickRadius, style: .continuous)
                        .fill(clayDeep)
                        .frame(width: brickW / 2 - colGap / 2, height: brickH)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
func renderPNG(side: Int) throws -> Data {
    // Render with `isOpaque = true` so ImageRenderer flattens the alpha
    // channel against the AppIconMark's cream background. Apple's HIG
    // requires opaque icons; iOS 26 notification icons specifically
    // refuse RGBA and silently fall back to the generic placeholder.
    let icon = AppIconMark(size: CGFloat(side))
        .frame(width: CGFloat(side), height: CGFloat(side))
    let renderer = ImageRenderer(content: icon)
    renderer.scale = 1
    renderer.isOpaque = true
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed at side=\(side)"])
    }
    return png
}

@MainActor
func render() throws {
    // iOS 26 notification icons read from explicit-size asset-catalog
    // entries, not from a single 1024 universal master. Without these
    // smaller renditions, notifications fall back to the generic
    // grey-square placeholder. (Home-screen icon still works because
    // the home-screen path scales the 1024 itself.)
    let sizes: [(name: String, side: Int)] = [
        ("AppIcon-20@2x.png", 40),
        ("AppIcon-20@3x.png", 60),
        ("AppIcon-29@2x.png", 58),
        ("AppIcon-29@3x.png", 87),
        ("AppIcon-40@2x.png", 80),
        ("AppIcon-40@3x.png", 120),
        ("AppIcon-60@2x.png", 120),
        ("AppIcon-60@3x.png", 180),
        ("AppIcon-1024.png", 1024),
    ]
    let dir = URL(fileURLWithPath: "Brick/Assets.xcassets/AppIcon.appiconset")
    var wrote = 0
    for (name, side) in sizes {
        let png = try renderPNG(side: side)
        let out = dir.appendingPathComponent(name)
        try png.write(to: out)
        wrote += png.count
        FileHandle.standardOutput.write(Data("  \(name) (\(side)px, \(png.count)B)\n".utf8))
    }
    FileHandle.standardOutput.write(Data("wrote \(sizes.count) PNGs (\(wrote)B total)\n".utf8))
}

// Use dispatchMain() instead of a semaphore on the main thread —
// ImageRenderer must run on the main actor and a `semaphore.wait()`
// here would deadlock against the @MainActor Task.
Task { @MainActor in
    do {
        try render()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
        exit(1)
    }
}
dispatchMain()
