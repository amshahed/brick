import SwiftUI

struct StatsCard: View {
    let today: TimeInterval
    let week: TimeInterval
    let quotaUsed: TimeInterval
    let streak: Int

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            tile(label: "Today", value: formatDuration(today))
            tile(label: "This week", value: formatDuration(week))
            tile(label: "Break quota", value: formatQuota(quotaUsed))
            tile(label: "Streak", value: formatStreak(streak))
        }
    }

    @ViewBuilder
    private func tile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds.rounded() / 60)
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func formatQuota(_ used: TimeInterval) -> String {
        let mins = Int((used / 60).rounded())
        let cap = Int(BreakQuotaEngine.quotaCap / 60)
        return "\(mins)m / \(cap)m"
    }

    private func formatStreak(_ days: Int) -> String {
        "\(days) day\(days == 1 ? "" : "s")"
    }
}
