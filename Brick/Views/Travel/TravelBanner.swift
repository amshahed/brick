import SwiftUI

struct TravelBanner: View {
    let period: TravelPeriod
    let now: Date
    var onDisable: () -> Void
    var onTapDetails: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accentMuted)
                    .frame(width: 40, height: 40)
                Image(systemName: "airplane")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .rotationEffect(.degrees(-20))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Travel mode active".uppercased())
                    .font(Theme.label)
                    .tracking(0.8)
                    .foregroundStyle(Theme.accent)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                HStack(spacing: Theme.Space.sm) {
                    Button("Disable", action: onDisable)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .font(.footnote.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Button("Details", action: onTapDetails)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.footnote.weight(.semibold))
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .cardSurface()
    }

    private var subtitle: String {
        if let endDate = period.endDate {
            return "Ends \(format(endDate))"
        }
        return "Since \(format(period.startDate))"
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
