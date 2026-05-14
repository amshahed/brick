import Foundation
import XCTest
@testable import Brick

/// Pure-time logic for `ScheduleClock.upcomingOccurrences`. Used by
/// ScheduleEngine to schedule the start/end notifications for the next
/// few days. Same anchor week as ScheduleClockActivityTests.
@MainActor
final class ScheduleOccurrenceTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    /// 2024-01-07 is a Sunday. Anchor on this so weekdays line up.
    private func date(weekday: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 1
        comps.day = 6 + weekday
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    /// Build a Schedule without persistence. SwiftData @Model classes can be
    /// instantiated outside a context; we never insert or fetch.
    private func make(
        weekdayMask: WeekdayMask,
        startMinute: Int,
        endMinute: Int,
        enabled: Bool = true,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> Schedule {
        Schedule(
            name: "Test",
            blocklist: nil,
            weekdayMask: weekdayMask,
            startMinute: startMinute,
            endMinute: endMinute,
            startDate: startDate,
            endDate: endDate,
            enabled: enabled
        )
    }

    func testNonWrapWeekdaysProducesOneOccurrencePerMatchingDay() {
        // 09:00–17:00 weekdays, starting Sunday → next 7 days has Mon..Fri.
        let schedule = make(weekdayMask: .weekdays, startMinute: 9 * 60, endMinute: 17 * 60)
        let now = date(weekday: 1, hour: 6, minute: 0)  // Sunday 06:00
        let occs = ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 7, calendar: calendar)
        XCTAssertEqual(occs.count, 5)
        XCTAssertEqual(occs.first?.start, date(weekday: 2, hour: 9, minute: 0))
        XCTAssertEqual(occs.first?.end, date(weekday: 2, hour: 17, minute: 0))
        XCTAssertEqual(occs.last?.start, date(weekday: 6, hour: 9, minute: 0))
    }

    func testWrapPastMidnightEndsOnFollowingDay() {
        // 22:00–02:00 every day. From Monday 21:00 with 1-day window we get
        // exactly one occurrence (Mon 22:00 → Tue 02:00).
        let schedule = make(weekdayMask: .all, startMinute: 22 * 60, endMinute: 2 * 60)
        let now = date(weekday: 2, hour: 21, minute: 0)
        let occs = ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 1, calendar: calendar)
        XCTAssertEqual(occs.count, 1)
        XCTAssertEqual(occs[0].start, date(weekday: 2, hour: 22, minute: 0))
        XCTAssertEqual(occs[0].end, date(weekday: 3, hour: 2, minute: 0))
    }

    func testWeekdayMaskFilteringSkipsExcludedDays() {
        // Mon/Wed/Fri only. Window covers a full week → 3 occurrences.
        let schedule = make(
            weekdayMask: [.mon, .wed, .fri],
            startMinute: 9 * 60,
            endMinute: 17 * 60
        )
        let now = date(weekday: 1, hour: 0, minute: 0)
        let occs = ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 7, calendar: calendar)
        XCTAssertEqual(occs.count, 3)
        XCTAssertEqual(occs.map(\.start), [
            date(weekday: 2, hour: 9, minute: 0),
            date(weekday: 4, hour: 9, minute: 0),
            date(weekday: 6, hour: 9, minute: 0),
        ])
    }

    func testEndDateCutoff() {
        // Schedule ends Tuesday. Window covers a week → only Mon, Tue.
        let schedule = make(
            weekdayMask: .weekdays,
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            endDate: date(weekday: 3, hour: 0, minute: 0)
        )
        let now = date(weekday: 1, hour: 0, minute: 0)
        let occs = ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 7, calendar: calendar)
        XCTAssertEqual(occs.count, 2)
        XCTAssertEqual(occs.map(\.start), [
            date(weekday: 2, hour: 9, minute: 0),
            date(weekday: 3, hour: 9, minute: 0),
        ])
    }

    func testStartDateExcludesEarlierDays() {
        // Schedule starts Wednesday. From Sunday with week window → Wed-Fri.
        let schedule = make(
            weekdayMask: .weekdays,
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            startDate: date(weekday: 4, hour: 0, minute: 0)
        )
        let now = date(weekday: 1, hour: 0, minute: 0)
        let occs = ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 7, calendar: calendar)
        XCTAssertEqual(occs.count, 3)
        XCTAssertEqual(occs.first?.start, date(weekday: 4, hour: 9, minute: 0))
    }

    func testDisabledScheduleReturnsEmpty() {
        let schedule = make(
            weekdayMask: .all,
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            enabled: false
        )
        let now = date(weekday: 1, hour: 0, minute: 0)
        XCTAssertTrue(
            ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 3, calendar: calendar).isEmpty
        )
    }

    func testInProgressOccurrenceIsKept() {
        // Schedule 09:00–17:00 weekdays. now is Monday 14:00 — start passed
        // but end is still in the future; we keep it so the END notification
        // can still be scheduled.
        let schedule = make(weekdayMask: .weekdays, startMinute: 9 * 60, endMinute: 17 * 60)
        let now = date(weekday: 2, hour: 14, minute: 0)
        let occs = ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 1, calendar: calendar)
        XCTAssertEqual(occs.count, 1)
        XCTAssertEqual(occs[0].start, date(weekday: 2, hour: 9, minute: 0))
        XCTAssertEqual(occs[0].end, date(weekday: 2, hour: 17, minute: 0))
    }

    func testFullyPastOccurrenceIsExcluded() {
        // Same schedule, but now is Monday 18:00 — already past today's end.
        // 1-day window has nothing left.
        let schedule = make(weekdayMask: .weekdays, startMinute: 9 * 60, endMinute: 17 * 60)
        let now = date(weekday: 2, hour: 18, minute: 0)
        let occs = ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 1, calendar: calendar)
        XCTAssertTrue(occs.isEmpty)
    }
}
