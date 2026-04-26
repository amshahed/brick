import FamilyControls
import ManagedSettings
import SwiftUI

struct ActiveBreakView: View {
    let active: BreakSessionController.ActiveBreak
    let onEndEarly: () -> Void

    @State private var now: Date = .now
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Label(active.appToken)
                .font(.title2.bold())
                .labelStyle(.titleAndIcon)

            Text(format(remaining: active.plannedEnd.timeIntervalSince(now)))
                .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.tint)
                .contentTransition(.numericText())

            Text("Break ends at \(active.plannedEnd.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive, action: onEndEarly) {
                Label("End break early", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("On break")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { now = $0 }
    }

    private func format(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
