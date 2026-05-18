import SwiftUI

/// The Brick app icon, drawn entirely from primitives so the asset can be
/// regenerated without an external tool. Render at 1024×1024 inside an
/// Xcode preview (or via the `render-app-icon.swift` script at the repo
/// root) and export to PNG for the AppIcon.appiconset.
///
/// Design intent: a warm-cream square holding a stylised brick wall —
/// two rows of three bricks, offset like real masonry, in the same clay
/// accent the app uses everywhere. No glyph, no wordmark; the silhouette
/// is the brand. Matches the "refined industrial" direction in
/// `Theme.swift`.
struct AppIconMark: View {
    /// Side length the icon renders at. 1024 for the App Store master;
    /// scale down in previews.
    var size: CGFloat = 1024

    private var cream: Color { Color(red: 0.964, green: 0.933, blue: 0.886) }
    private var clay: Color { Color(red: 0.722, green: 0.361, blue: 0.220) }
    private var clayDeep: Color { Color(red: 0.612, green: 0.286, blue: 0.149) }

    var body: some View {
        ZStack {
            // No outer corner rounding — iOS masks the icon itself. Filling
            // the full square keeps the cream tone right up to the edge.
            Rectangle().fill(cream)

            // Two-row brick stack, centred. Each brick is a rounded rect
            // sized as a fraction of the canvas so the layout scales with
            // `size`.
            let unit = size / 12              // base grid unit
            let brickW = unit * 3
            let brickH = unit * 1.6
            let brickRadius = unit * 0.32
            let rowGap = unit * 0.45
            let colGap = unit * 0.4

            VStack(spacing: rowGap) {
                // Top row: 3 full bricks
                HStack(spacing: colGap) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: brickRadius, style: .continuous)
                            .fill(clay)
                            .frame(width: brickW, height: brickH)
                    }
                }
                // Bottom row: shifted half-brick for the masonry offset.
                // Edges get clipped half-bricks; middle gets two full bricks.
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

#Preview("App icon — 1024") {
    AppIconMark(size: 1024)
        .frame(width: 320, height: 320)
        .scaleEffect(320.0 / 1024.0)
}

#Preview("App icon — 180") {
    AppIconMark(size: 180)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
}
