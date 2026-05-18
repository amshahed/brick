import FamilyControls
import ManagedSettings
import SwiftUI

struct ActiveBreakView: View {
    let active: BreakSessionController.ActiveBreak
    let onEndEarly: () -> Void

    var body: some View {
        // Centered ring composition. The countdown text sits inside a
        // CountdownRing that drains as time elapses; elapsed/total numbers
        // sit beneath, and the target (app or category) label sits above.
        // TimelineView drives the per-second redraw — `Timer.publish` on a
        // stored View property stopped firing once SwiftUI re-created the
        // struct (#25), and the ring's animation lives inside the shared
        // `CountdownRing` primitive in `Theme.swift`.
        TimelineView(.periodic(from: active.startedAt, by: 1)) { context in
            let now = context.date
            let remaining = max(0, active.plannedEnd.timeIntervalSince(now))
            let elapsed = max(0, now.timeIntervalSince(active.startedAt))

            VStack(spacing: Theme.Space.xl) {
                VStack(spacing: Theme.Space.sm) {
                    Text("On break".uppercased())
                        .font(Theme.label)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    targetLabel
                        .font(Theme.display(22, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                        .multilineTextAlignment(.center)
                }

                CountdownRing(
                    start: active.startedAt,
                    end: active.plannedEnd,
                    lineWidth: 14
                ) {
                    VStack(spacing: 4) {
                        Text(format(remaining: remaining))
                            .font(Theme.statNumber(58, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                        Text("Ends at \(active.plannedEnd.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 260, height: 260)

                HStack(spacing: 0) {
                    StatBlock(value: format(remaining: elapsed), label: "Elapsed", alignment: .center, numberSize: 22)
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1, height: 28)
                    StatBlock(value: format(remaining: active.plannedEnd.timeIntervalSince(active.startedAt)), label: "Total", alignment: .center, numberSize: 22)
                }
                .cardSurface()
                .frame(maxWidth: 360)

                Spacer(minLength: 0)

                Button(action: onEndEarly) {
                    Label("End break early", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.brickSecondary)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.xl)
            .padding(.bottom, Theme.Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("On break")
            .navigationBarTitleDisplayMode(.inline)
        }
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
