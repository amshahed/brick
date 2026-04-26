import Foundation
import SwiftData
import XCTest
@testable import Brick

@MainActor
final class NotificationFormattingTests: XCTestCase {

    // MARK: - Total blocked text

    func testFormatTotalBlockedUnderAnHour() {
        XCTAssertEqual(NotificationService.formatTotalBlocked(0), "0m")
        XCTAssertEqual(NotificationService.formatTotalBlocked(5 * 60), "5m")
        XCTAssertEqual(NotificationService.formatTotalBlocked(59 * 60), "59m")
    }

    func testFormatTotalBlockedOverAnHour() {
        XCTAssertEqual(NotificationService.formatTotalBlocked(60 * 60), "1h 0m")
        XCTAssertEqual(NotificationService.formatTotalBlocked(90 * 60), "1h 30m")
        XCTAssertEqual(NotificationService.formatTotalBlocked((2 * 60 + 15) * 60), "2h 15m")
    }

    // MARK: - Overage text

    func testFormatOverage() {
        let text = NotificationService.formatOverage(overage: 300, extensionApplied: 600)
        XCTAssertEqual(text, "Block extended by 10 min (5 min overage × 2).")
    }

    func testFormatOverageRoundsToMinutes() {
        // 123s overage → 2m (rounded); 246s extension → 4m (rounded)
        let text = NotificationService.formatOverage(overage: 123, extensionApplied: 246)
        XCTAssertEqual(text, "Block extended by 4 min (2 min overage × 2).")
    }

    // MARK: - Today's totals

    func testTotalBlockedTodayClampsToMidnight() throws {
        let context = try InMemoryStore.make()
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        let midnight = cal.startOfDay(for: noon)
        // A session that started yesterday at 11pm and ended today at 1am:
        // only the 1-hour portion (midnight..1am) should count.
        let yesterdayEleven = midnight.addingTimeInterval(-3600)
        let todayOne = midnight.addingTimeInterval(3600)
        let s = Schedule(
            name: "Overnight",
            blocklist: nil,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        context.insert(s)
        let session = BlockSession(
            schedule: s,
            actualStart: yesterdayEleven,
            coldStartEnd: yesterdayEleven,
            scheduledEnd: todayOne
        )
        session.actualEnd = todayOne
        context.insert(session)
        try context.save()

        let total = NotificationService.totalBlockedToday(context: context, now: noon)
        XCTAssertEqual(total, 3600, accuracy: 1)
    }

    func testTotalBlockedTodayIgnoresYesterdayOnlySessions() throws {
        let context = try InMemoryStore.make()
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        let midnight = cal.startOfDay(for: noon)
        let yesterdayStart = midnight.addingTimeInterval(-7200)
        let yesterdayEnd = midnight.addingTimeInterval(-3600)
        let s = Schedule(
            name: "Yesterday",
            blocklist: nil,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        context.insert(s)
        let session = BlockSession(
            schedule: s,
            actualStart: yesterdayStart,
            coldStartEnd: yesterdayStart,
            scheduledEnd: yesterdayEnd
        )
        session.actualEnd = yesterdayEnd
        context.insert(session)
        try context.save()

        let total = NotificationService.totalBlockedToday(context: context, now: noon)
        XCTAssertEqual(total, 0, accuracy: 1)
    }

    func testTotalBlockedTodayIncludesOpenSessionUpToNow() throws {
        let context = try InMemoryStore.make()
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        let start = now.addingTimeInterval(-1800) // 30 min ago
        let s = Schedule(
            name: "Now",
            blocklist: nil,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        context.insert(s)
        let session = BlockSession(
            schedule: s,
            actualStart: start,
            coldStartEnd: start,
            scheduledEnd: now.addingTimeInterval(3600)
        )
        context.insert(session)
        try context.save()

        let total = NotificationService.totalBlockedToday(context: context, now: now)
        XCTAssertEqual(total, 1800, accuracy: 1)
    }
}
