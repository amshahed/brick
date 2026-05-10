import FamilyControls
import ManagedSettings
import SwiftUI

struct ActiveBreakView: View {
    let active: BreakSessionController.ActiveBreak
    let onEndEarly: () -> Void

    @State private var now: Date = .now
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionEyebrow(text: "On break")
                targetLabel
                    .font(Theme.display(28, weight: .semibold))
                    .labelStyle(.titleAndIcon)
            }

            // Big monospaced countdown — the screen's center of gravity.
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(format(remaining: active.plannedEnd.timeIntervalSince(now)))
                    .font(Theme.statNumber(72, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                Text("Ends at \(active.plannedEnd.formatted(date: .omitted, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.xl)

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
        .onReceive(ticker) { now = $0 }
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
