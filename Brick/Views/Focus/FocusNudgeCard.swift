import SwiftUI

struct FocusNudgeCard: View {
    var onSetUp: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "moon.circle.fill")
                .font(.title)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Let important calls through")
                    .font(.headline)
                Text("Pair Brick with a Focus mode so family and on-call can still reach you during blocks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Set up Focus", action: onSetUp)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
    }
}
