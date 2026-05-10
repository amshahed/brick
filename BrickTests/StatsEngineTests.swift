import Foundation
import SwiftData
import XCTest
@testable import Brick

@MainActor
final class StatsEngineTests: XCTestCase {
    var context: ModelContext!
    var engine: StatsEngine!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
        engine = StatsEngine(context: context)
    }

    // MARK: - Helpers

    private func makeSchedule(name: String = "S") -> Schedule {
        let s = Schedule(
            name: name,
            blocklist: nil,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        context.insert(s)
        return s
    }

    private func insertSession(
        schedule: Schedule,
        start: Date,
        end: Date?
    ) {
        let session = BlockSession(
            schedule: schedule,
            actualStart: start,
            coldStartEnd: start,
            scheduledEnd: end ?? start.addingTimeInterval(3600)
        )
        session.actualEnd = end
        context.insert(session)
    }

    // MARK: - blocked today / week

    func testBlockedTodayCountsOpenSessionUpToNow() throws {
        let schedule = makeSchedule()
        let now = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now) ?? .now
        insertSession(schedule: schedule, start: now.addingTimeInterval(-1800), end: nil)
        try context.save()

        XCTAssertEqual(engine.blockedToday(now: now), 1800, accuracy: 1)
    }

    func testBlockedTodayIgnoresYesterdaySession() throws {
        let schedule = makeSchedule()
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        let midnight = Calendar.current.startOfDay(for: now)
        insertSession(
            schedule: schedule,
            start: midnight.addingTimeInterval(-7200),
            end: midnight.addingTimeInterval(-3600)
        )
        try context.save()

        XCTAssertEqual(engine.blockedToday(now: now), 0, accuracy: 1)
    }

    func testBlockedThisWeekCoversMultipleDays() throws {
        let schedule = makeSchedule()
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        insertSession(
            schedule: schedule,
            start: weekStart.addingTimeInterval(3600),
            end: weekStart.addingTimeInterval(3600 + 1800)
        )
        insertSession(
            schedule: schedule,
            start: weekStart.addingTimeInterval(86400 + 3600),
            end: weekStart.addingTimeInterval(86400 + 3600 + 1800)
        )
        try context.save()

        XCTAssertEqual(engine.blockedThisWeek(now: now), 3600, accuracy: 1)
    }

    // MARK: - Quota

    func testQuotaUsedZeroWhenNoActiveSession() {
        XCTAssertEqual(engine.quotaUsed(), 0, accuracy: 1)
    }

    // MARK: - Streak

    func testStreakZeroWithNoRecords() {
        XCTAssertEqual(engine.onQuotaStreak(), 0)
    }

    func testStreakCountsOnQuotaDaysEndingYesterday() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        context.insert(BreakRecord(
            blockSession: nil,
            startTime: yesterday.addingTimeInterval(3600),
            appTokenData: Data(),
            wasOverage: false,
            plannedDuration: 300
        ))
        context.insert(BreakRecord(
            blockSession: nil,
            startTime: twoDaysAgo.addingTimeInterval(3600),
            appTokenData: Data(),
            wasOverage: false,
            plannedDuration: 300
        ))
        try context.save()

        // Today has no records, so we start from yesterday.
        XCTAssertEqual(engine.onQuotaStreak(now: today.addingTimeInterval(3600)), 2)
    }

    func testStreakResetsOnOverageDay() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        // Yesterday: on-quota. Two days ago: overage (resets).
        context.insert(BreakRecord(
            blockSession: nil,
            startTime: yesterday.addingTimeInterval(3600),
            appTokenData: Data(),
            wasOverage: false,
            plannedDuration: 300
        ))
        context.insert(BreakRecord(
            blockSession: nil,
            startTime: twoDaysAgo.addingTimeInterval(3600),
            appTokenData: Data(),
            wasOverage: true,
            plannedDuration: 300
        ))
        try context.save()

        XCTAssertEqual(engine.onQuotaStreak(now: today.addingTimeInterval(3600)), 1)
    }

    func testStreakIgnoresEmptyDays() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!

        // Only one record, 3 days ago, on-quota. Days in between are empty.
        context.insert(BreakRecord(
            blockSession: nil,
            startTime: threeDaysAgo.addingTimeInterval(3600),
            appTokenData: Data(),
            wasOverage: false,
            plannedDuration: 300
        ))
        try context.save()

        // Empty days don't reset the walk — the engine still finds the
        // recorded day 3 days back and counts it (streak = 1). The walk
        // doesn't keep going forever past the earliest recorded day.
        let streak = engine.onQuotaStreak(now: today.addingTimeInterval(3600))
        XCTAssertEqual(streak, 1)
    }
}
