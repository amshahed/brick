import SwiftUI

/// 2×2 grid of stat tiles. Each tile is a `StatTile` (icon plate + value
/// + small-caps label) wrapped in `cardSurface()`, so the four cells read
/// as a coherent band on the home screen.
struct StatsCard: View {
    let today: TimeInterval
    let week: TimeInterval
    let quotaUsed: TimeInterval
    let streak: Int

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.sm),
        GridItem(.flexible(), spacing: Theme.Space.sm)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionEyebrow(text: "Your week")
            LazyVGrid(columns: columns, spacing: Theme.Space.sm) {
                StatTile(symbol: "hourglass", value: formatDuration(today), label: "Today")
                StatTile(symbol: "calendar", value: formatDuration(week), label: "This week")
                StatTile(
                    symbol: "gauge.with.dots.needle.50percent",
                    value: formatQuota(quotaUsed),
                    label: "Break quota"
                )
                StatTile(symbol: "flame.fill", value: formatStreak(streak), label: "Streak")
            }
        }
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
