import FamilyControls
import ManagedSettings
import SwiftUI

struct ActiveBreakView: View {
    let active: BreakSessionController.ActiveBreak
    let onEndEarly: () -> Void

    var body: some View {
        // TimelineView gives us a managed periodic redraw — every second
        // the closure re-runs with a fresh `context.date`. Replaces the
        // earlier `Timer.publish(...).autoconnect()` + @State pattern,
        // which silently stopped firing once SwiftUI re-created the View
        // struct (the autoconnect subscription was tied to a stored
        // property that didn't survive re-creation). (#25)
        TimelineView(.periodic(from: active.startedAt, by: 1)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionEyebrow(text: "On break")
                    targetLabel
                        .font(Theme.display(28, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                }

                // Big monospaced countdown — the screen's center of gravity.
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text(format(remaining: active.plannedEnd.timeIntervalSince(now)))
                        .font(Theme.statNumber(72, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    progressBar(now: now)
                    Text("Ends at \(active.plannedEnd.formatted(date: .omitted, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Space.lg)

                Spacer()

                Button(action: onEndEarly) {
                    Label("End break early", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.brickSecondary)
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("On break")
            .navigationBarTitleDisplayMode(.inline)
        }
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
        let total = active.plannedEnd.timeIntervalSince(active.startedAt)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(active.startedAt)
        return max(0, min(1, 1 - elapsed / total))
    }

    @ViewBuilder
    private var targetLabel: some View {
        switch active.target {
        case .app(let token):
            Label(token)
        case .category(let token):
            Label(token)
        }
    }

    private func format(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
