import SwiftUI

struct StatsCard: View {
    let today: TimeInterval
    let week: TimeInterval
    let quotaUsed: TimeInterval
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            SectionEyebrow(text: "Your week")

            // Two-column grid of large monospaced stats. The hairline
            // dividers between cells keep the rhythm without adding the
            // weight of full card-on-card chrome.
            HStack(alignment: .top, spacing: 0) {
                StatBlock(value: formatDuration(today), label: "Today", numberSize: 30)
                Divider().frame(height: 56).overlay(Theme.hairline)
                StatBlock(value: formatDuration(week), label: "This week", numberSize: 30)
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Theme.hairline)

            HStack(alignment: .top, spacing: 0) {
                StatBlock(value: formatQuota(quotaUsed), label: "Break quota", numberSize: 22)
                Divider().frame(height: 44).overlay(Theme.hairline)
                StatBlock(value: formatStreak(streak), label: "Streak", numberSize: 22)
            }
            .frame(maxWidth: .infinity)
        }
        .cardSurface()
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
        return "\(mins) / \(cap)m"
    }

    private func formatStreak(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}
