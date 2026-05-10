import SwiftUI

struct ActiveBlockCard: View {
    let oneShots: [OneShotBlock]
    let now: Date
    let onAddAnother: () -> Void
    var onCancelOneShot: (OneShotBlock) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    Circle()
                        .fill(Theme.accentMuted)
                        .frame(width: 38, height: 38)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                        .opacity(pulseOpacity)
                        .animation(
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                            value: pulseOpacity
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block active".uppercased())
                        .font(Theme.label)
                        .tracking(0.8)
                        .foregroundStyle(Theme.accent)
                    Text(headline)
                        .font(Theme.display(20, weight: .semibold))
                }
                Spacer()
            }

            // One-shot rows. Each is a full-width line with name, timer,
            // and a quiet cancel affordance.
            if !oneShots.isEmpty {
                VStack(spacing: Theme.Space.sm) {
                    ForEach(oneShots) { oneShot in
                        oneShotRow(oneShot)
                    }
                }
            }

            Button(action: onAddAnother) {
                Label("Add another block", systemImage: "plus")
            }
            .buttonStyle(.brickSecondary)
        }
        .cardSurface()
        .onAppear { pulseOpacity = 0.35 }
    }

    @State private var pulseOpacity: Double = 1.0

    private var headline: String {
        if oneShots.count == 1, let only = oneShots.first {
            return only.blocklist?.name ?? "Block running"
        }
        if oneShots.isEmpty { return "On schedule" }
        return "\(oneShots.count) blocks running"
    }

    @ViewBuilder
    private func oneShotRow(_ oneShot: OneShotBlock) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(oneShot.blocklist?.name ?? "Unknown")
                    .font(Theme.display(15, weight: .semibold))
                Text(oneShot.blocklist?.selectionSummary ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.sm)
            Text(format(remaining: oneShot.expiresAt.timeIntervalSince(now)))
                .font(Theme.statNumber(18, weight: .medium))
                .foregroundStyle(.primary)
            Button {
                onCancelOneShot(oneShot)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel \(oneShot.blocklist?.name ?? "block")")
        }
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func format(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
