import SwiftUI

struct FocusNudgeCard: View {
    var onSetUp: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accentMuted)
                    .frame(width: 40, height: 40)
                Image(systemName: "moon.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Let important calls through")
                        .font(Theme.display(15, weight: .semibold))
                    Text("Pair Brick with a Focus mode so family and on-call can still reach you during blocks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Set up Focus", action: onSetUp)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                    .font(.footnote.weight(.semibold))
            }
            Spacer(minLength: Theme.Space.sm)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .cardSurface()
    }
}
