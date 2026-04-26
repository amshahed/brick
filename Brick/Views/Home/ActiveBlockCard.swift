import SwiftUI

struct ActiveBlockCard: View {
    let oneShots: [OneShotBlock]
    let now: Date
    let onAddAnother: () -> Void
    var onCancelOneShot: (OneShotBlock) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Block active")
                .font(.title3.bold())

            VStack(spacing: 8) {
                ForEach(oneShots) { oneShot in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(oneShot.blocklist?.name ?? "Unknown")
                                .font(.headline)
                            Text(oneShot.blocklist?.selectionSummary ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(format(remaining: oneShot.expiresAt.timeIntervalSince(now)))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.tint)
                        Button {
                            onCancelOneShot(oneShot)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel \(oneShot.blocklist?.name ?? "block")")
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 12))
                }
            }

            Button(action: onAddAnother) {
                Label("Add another block", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
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
