import Foundation
import XCTest
@testable import Brick

/// Pure-time logic for the schedule activity check. Covers PRD user
/// stories 3 (recurring with weekday mask), 4 (bounded with start/end
/// dates), 5 (perpetual with no end date), and the wrap-past-midnight
/// case for templates like Night Wind-Down.
final class ScheduleClockActivityTests: XCTestCase {
    /// Build a Date for a given weekday (Apple weekday: 1 = Sun … 7 = Sat),
    /// hour, and minute — anchored on a known reference week so tests stay
    /// deterministic regardless of the host clock.
    private func date(weekday: Int, hour: Int, minute: Int) -> Date {
        // 2024-01-07 is a Sunday — pick this as the week base so weekday 1
        // lines up cleanly. Add (weekday - 1) days to land on the desired day.
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 1
        comps.day = 6 + weekday  // weekday=1 → Jan 7 (Sun), 2 → Jan 8 (Mon), ...
        comps.hour = hour
        comps.minute = minute
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    func testWeekdaysMaskCoversMonday() {
        let monday = date(weekday: 2, hour: 8, minute: 0)
        XCTAssertTrue(ScheduleClock.isActive(
            weekdayMask: .weekdays,
            startMinute: 6 * 60,
            endMinute: 10 * 60,
            startDate: nil, endDate: nil,
            at: monday
        ))
    }

    func testWeekdaysMaskExcludesSaturday() {
        let saturday = date(weekday: 7, hour: 8, minute: 0)
        XCTAssertFalse(ScheduleClock.isActive(
            weekdayMask: .weekdays,
            startMinute: 6 * 60,
            endMinute: 10 * 60,
            startDate: nil, endDate: nil,
            at: saturday
        ))
    }

    func testOutsideTimeWindowIsInactive() {
        // 11:00 — outside a 6–10 morning window even on a covered weekday.
        let monday11 = date(weekday: 2, hour: 11, minute: 0)
        XCTAssertFalse(ScheduleClock.isActive(
            weekdayMask: .weekdays,
            startMinute: 6 * 60,
            endMinute: 10 * 60,
            startDate: nil, endDate: nil,
            at: monday11
        ))
    }

    /// Night Wind-Down template: 22:00–07:00 daily, wraps past midnight.
    /// 23:00 on a covered day is in the pre-midnight half and must be active.
    func testWrapPastMidnightActiveBeforeMidnight() {
        let mon23 = date(weekday: 2, hour: 23, minute: 0)
        XCTAssertTrue(ScheduleClock.isActive(
            weekdayMask: .all,
            startMinute: 22 * 60,
            endMinute: 7 * 60,
            startDate: nil, endDate: nil,
            at: mon23
        ))
    }

    /// Continuation of the wrap: 05:00 the next day must still be active
    /// because the previous day started the occurrence.
    func testWrapPastMidnightActiveAfterMidnight() {
        let tue05 = date(weekday: 3, hour: 5, minute: 0)
        XCTAssertTrue(ScheduleClock.isActive(
            weekdayMask: .all,
            startMinute: 22 * 60,
            endMinute: 7 * 60,
            startDate: nil, endDate: nil,
            at: tue05
        ))
    }

    /// PRD user story 4 — bounded period: schedule should only fire inside
    /// its [startDate, endDate] window. Picking a date inside the window on
    /// a covered weekday + time should be active.
    func testBoundedScheduleActiveInsideWindow() {
        let inside = date(weekday: 2, hour: 9, minute: 0)
        let weekBefore = inside.addingTimeInterval(-7 * 24 * 3600)
        let weekAfter = inside.addingTimeInterval(7 * 24 * 3600)

        XCTAssertTrue(ScheduleClock.isActive(
            weekdayMask: .weekdays,
            startMinute: 8 * 60,
            endMinute: 22 * 60,
            startDate: weekBefore,
            endDate: weekAfter,
            at: inside
        ))
    }

    func testBoundedScheduleInactiveBeforeStartDate() {
        let probe = date(weekday: 2, hour: 9, minute: 0)
        let startDate = probe.addingTimeInterval(7 * 24 * 3600)
        let endDate = probe.addingTimeInterval(14 * 24 * 3600)

        XCTAssertFalse(ScheduleClock.isActive(
            weekdayMask: .weekdays,
            startMinute: 8 * 60,
            endMinute: 22 * 60,
            startDate: startDate,
            endDate: endDate,
            at: probe
        ))
    }

    func testBoundedScheduleInactiveAfterEndDate() {
        let probe = date(weekday: 2, hour: 9, minute: 0)
        let startDate = probe.addingTimeInterval(-14 * 24 * 3600)
        let endDate = probe.addingTimeInterval(-7 * 24 * 3600)

        XCTAssertFalse(ScheduleClock.isActive(
            weekdayMask: .weekdays,
            startMinute: 8 * 60,
            endMinute: 22 * 60,
            startDate: startDate,
            endDate: endDate,
            at: probe
        ))
    }
}
