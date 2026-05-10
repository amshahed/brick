import SwiftUI

/// Card-style row used in the Blocklists list. Replaces the default
/// list-row look with the Theme card surface so the list breathes.
struct BlocklistRow: View {
    let blocklist: Blocklist

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accentMuted)
                    .frame(width: 40, height: 40)
                Image(systemName: "square.stack")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(blocklist.name)
                    .font(Theme.display(17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(blocklist.selectionSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .cardSurface(padding: Theme.Space.md)
        .contentShape(Rectangle())
    }
}
