import Foundation
import SwiftData

/// Pure read-side computations for the Home tab dashboard. Views call these
/// on whatever cadence they want (typically once per second). No caching —
/// the dataset is tiny so we just re-fetch.
struct StatsEngine {
    let context: ModelContext

    // MARK: - Blocked time

    func blockedToday(now: Date = .now) -> TimeInterval {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
        return blocked(in: start..<end, now: now)
    }

    func blockedThisWeek(now: Date = .now) -> TimeInterval {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else {
            return 0
        }
        return blocked(in: interval.start..<interval.end, now: now)
    }

    private func blocked(in window: Range<Date>, now: Date) -> TimeInterval {
        let sessions = (try? context.fetch(FetchDescriptor<BlockSession>())) ?? []
        return sessions.reduce(0) { sum, session in
            let sessionEnd = session.actualEnd ?? now
            let overlapStart = max(session.actualStart, window.lowerBound)
            let overlapEnd = min(sessionEnd, window.upperBound)
            guard overlapEnd > overlapStart else { return sum }
            return sum + overlapEnd.timeIntervalSince(overlapStart)
        }
    }

    // MARK: - Quota

    /// 0...`quotaCap` — elapsed break time in the rolling 60-min window. Zero
    /// when no active block session (the engine returns `.noActiveBlock`).
    func quotaUsed(now: Date = .now) -> TimeInterval {
        let engine = BreakQuotaEngine(context: context)
        let remaining = (try? engine.remainingQuota(at: now)) ?? BreakQuotaEngine.quotaCap
        return max(0, BreakQuotaEngine.quotaCap - remaining)
    }

    // MARK: - Streak

    /// Consecutive on-quota days (ending today or yesterday). Each day with
    /// at least one non-overage record adds 1. Empty days within recorded
    /// history are gaps — they don't reset the streak but don't extend it
    /// either. The walk stops on the first overage day, or when the cursor
    /// passes the earliest recorded day.
    func onQuotaStreak(now: Date = .now) -> Int {
        let cal = Calendar.current
        let records = (try? context.fetch(FetchDescriptor<BreakRecord>())) ?? []
        if records.isEmpty { return 0 }

        let overageDays: Set<Date> = Set(
            records
                .filter { $0.wasOverage }
                .map { cal.startOfDay(for: $0.startTime) }
        )
        let recordDays: Set<Date> = Set(
            records.map { cal.startOfDay(for: $0.startTime) }
        )
        guard let earliestRecordDay = recordDays.min() else { return 0 }

        var streak = 0
        var cursor = cal.startOfDay(for: now)
        // If today has no records yet, start the walk from yesterday so we
        // don't artificially inflate the streak with an empty in-progress day.
        if !recordDays.contains(cursor) {
            guard let y = cal.date(byAdding: .day, value: -1, to: cursor) else {
                return 0
            }
            cursor = y
        }

        while cursor >= earliestRecordDay {
            if overageDays.contains(cursor) { break }
            if recordDays.contains(cursor) { streak += 1 }
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = prev
        }
        return streak
    }
}
