import SwiftUI

struct TravelBanner: View {
    let period: TravelPeriod
    let now: Date
    var onDisable: () -> Void
    var onTapDetails: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "airplane")
                .font(.title2)
                .foregroundStyle(.tint)
                .rotationEffect(.degrees(-20))
            VStack(alignment: .leading, spacing: 4) {
                Text("Travel mode active")
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Disable", action: onDisable)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                    Button("Details", action: onTapDetails)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14))
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
