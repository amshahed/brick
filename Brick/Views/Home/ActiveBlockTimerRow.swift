import SwiftUI

/// Live block-progress row for the home screen. Shows an elapsed-forward
/// progress bar, an elapsed `h:mm:ss` timer, the schedule/one-shot's name,
/// and the blocklist summary. Whole row is the primary tap target — taps
/// open the break sheet. One-shots get an additional `×` cancel affordance
/// (the only place to cancel a one-shot from the UI). (#35)
struct ActiveBlockTimerRow: View {
    let name: String
    let actualStart: Date
    let scheduledEnd: Date
    let subtitle: String
    let onCancel: (() -> Void)?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TimelineView(.periodic(from: actualStart, by: 1)) { context in
                body(now: context.date)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func body(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block active".uppercased())
                        .font(Theme.label)
                        .tracking(0.8)
                        .foregroundStyle(Theme.accent)
                    Text(name)
                        .font(Theme.display(20, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Space.sm)
                if let onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel \(name)")
                }
            }

            progressBar(now: now)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                Text(elapsed(now: now))
                    .font(Theme.statNumber(28, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("/ \(total())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private func progressBar(now: Date) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: geo.size.width * progressFraction(now: now))
                    .animation(.linear(duration: 0.9), value: progressFraction(now: now))
            }
        }
        .frame(height: 6)
    }

    private func progressFraction(now: Date) -> Double {
        let total = scheduledEnd.timeIntervalSince(actualStart)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(actualStart)
        return max(0, min(1, elapsed / total))
    }

    private func elapsed(now: Date) -> String {
        format(seconds: max(0, now.timeIntervalSince(actualStart)))
    }

    private func total() -> String {
        format(seconds: max(0, scheduledEnd.timeIntervalSince(actualStart)))
    }

    private func format(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
