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
func render() throws {
    let icon = AppIconMark(size: 1024).frame(width: 1024, height: 1024)
    let renderer = ImageRenderer(content: icon)
    renderer.scale = 1
    guard let nsImage = renderer.nsImage else {
        throw NSError(domain: "render", code: 1, userInfo: [NSLocalizedDescriptionKey: "nsImage was nil"])
    }
    guard let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render", code: 2, userInfo: [NSLocalizedDescriptionKey: "png encode failed"])
    }
    let out = URL(fileURLWithPath: "Brick/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    try png.write(to: out)
    FileHandle.standardOutput.write(Data("wrote \(out.path) (\(png.count) bytes)\n".utf8))
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
