import SwiftUI

/// Compact "ongoing break" card for the home screen. Surfaces the live
/// countdown without forcing the user back into the break sheet, and taps
/// through to the full break view so they can see what's unblocked or end
/// the break early.
struct ActiveBreakCard: View {
    let active: BreakSessionController.ActiveBreak
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // TimelineView drives the per-second redraw via SwiftUI's managed
            // schedule — same pattern as ActiveBreakView (#25), and survives
            // view-struct re-creation that broke the old Timer.publish setup.
            TimelineView(.periodic(from: active.startedAt, by: 1)) { context in
                row(now: context.date)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func row(now: Date) -> some View {
        HStack(spacing: Theme.Space.md) {
            ZStack {
                Circle()
                    .fill(Theme.accentMuted)
                    .frame(width: 38, height: 38)
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Break running".uppercased())
                    .font(Theme.label)
                    .tracking(0.8)
                    .foregroundStyle(Theme.accent)
                Text("Tap to view what's unblocked")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.sm)

            Text(format(remaining: active.plannedEnd.timeIntervalSince(now)))
                .font(Theme.statNumber(22, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
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
