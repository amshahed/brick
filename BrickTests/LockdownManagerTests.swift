import Foundation
import SwiftData
import XCTest
@testable import Brick

@MainActor
final class LockdownManagerTests: XCTestCase {
    var context: ModelContext!
    var lockdown: LockdownManager!
    var blocklist: Blocklist!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
        lockdown = LockdownManager(context: context)
        blocklist = Blocklist(name: "Test")
        context.insert(blocklist)
        try context.save()
    }

    // MARK: - Schedules

    func testDisableScheduleLockedWhenActive() throws {
        let now = Date.now
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .weekday], from: now)
        let weekday = comps.weekday ?? 1
        let startMin = ScheduleClock.minutes(from: comps.hour ?? 0, minute: comps.minute ?? 0) - 10
        let endMin = startMin + 120
        let schedule = Schedule(
            name: "Now",
            blocklist: blocklist,
            weekdayMask: WeekdayMask.forAppleWeekday(weekday),
            startMinute: max(0, startMin),
            endMinute: min(24 * 60 - 1, endMin)
        )
        context.insert(schedule)
        try context.save()

        XCTAssertTrue(lockdown.isLocked(.disableSchedule(schedule), at: now))
        XCTAssertTrue(lockdown.isLocked(.deleteSchedule(schedule), at: now))
        XCTAssertTrue(
            lockdown.isLocked(.editScheduleFields(schedule), at: now),
            "Editing the load-bearing fields of an active schedule must require the passcode."
        )
    }

    func testEditScheduleFieldsUnlockedWhenInactive() throws {
        // Off-hours schedule (1–2am, evaluated at noon the same day) — same
        // shape as testScheduleNotLockedOutsideWindow but asserting on the
        // editScheduleFields action specifically.
        let comps = DateComponents(year: 2024, month: 1, day: 8, hour: 12)
        let noon = Calendar.current.date(from: comps) ?? .now
        let oneAM = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 8, hour: 1)) ?? .now
        let weekday = Calendar.current.component(.weekday, from: oneAM)
        let schedule = Schedule(
            name: "Night",
            blocklist: blocklist,
            weekdayMask: WeekdayMask.forAppleWeekday(weekday),
            startMinute: 60,
            endMinute: 120
        )
        context.insert(schedule)
        try context.save()
        XCTAssertFalse(lockdown.isLocked(.editScheduleFields(schedule), at: noon))
    }

    func testScheduleNotLockedWhenDisabled() throws {
        let schedule = Schedule(
            name: "Off",
            blocklist: blocklist,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        schedule.enabled = false
        context.insert(schedule)
        try context.save()
        XCTAssertFalse(lockdown.isLocked(.disableSchedule(schedule)))
    }

    func testScheduleNotLockedOutsideWindow() throws {
        // A Monday-only 1am-2am schedule evaluated at noon on the same day.
        let monday = Date(timeIntervalSince1970: 1_700_006_400) // 2023-11-14 Tue? fine, we set the weekday below.
        var comps = DateComponents(year: 2024, month: 1, day: 8, hour: 12) // Mon noon
        let noon = Calendar.current.date(from: comps) ?? monday
        comps.hour = 1
        let oneAM = Calendar.current.date(from: comps) ?? monday
        let weekday = Calendar.current.component(.weekday, from: oneAM)
        let schedule = Schedule(
            name: "Night",
            blocklist: blocklist,
            weekdayMask: WeekdayMask.forAppleWeekday(weekday),
            startMinute: 60,
            endMinute: 120
        )
        context.insert(schedule)
        try context.save()
        XCTAssertFalse(lockdown.isLocked(.disableSchedule(schedule), at: noon))
    }

    // MARK: - One-shots

    func testOneShotLockedWhileActive() throws {
        let now = Date.now
        let oneShot = OneShotBlock(blocklist: blocklist, startedAt: now.addingTimeInterval(-60), duration: 600)
        context.insert(oneShot)
        try context.save()
        XCTAssertTrue(lockdown.isLocked(.cancelOneShot(oneShot), at: now))
    }

    func testOneShotUnlockedAfterExpiry() throws {
        let past = Date.now.addingTimeInterval(-3600)
        let oneShot = OneShotBlock(blocklist: blocklist, startedAt: past, duration: 60)
        context.insert(oneShot)
        try context.save()
        XCTAssertFalse(lockdown.isLocked(.cancelOneShot(oneShot)))
    }

    // MARK: - Blocklist enforcement

    func testBlocklistLockedWhenReferencedByActiveOneShot() throws {
        let now = Date.now
        let oneShot = OneShotBlock(blocklist: blocklist, startedAt: now.addingTimeInterval(-10), duration: 600)
        context.insert(oneShot)
        try context.save()
        XCTAssertTrue(lockdown.isLocked(.editBlocklist(blocklist), at: now))
        XCTAssertTrue(lockdown.isLocked(.deleteBlocklist(blocklist), at: now))
    }

    func testBlocklistUnlockedWhenNoActiveReferences() throws {
        // Expired one-shot referencing this blocklist should not lock it.
        let oneShot = OneShotBlock(
            blocklist: blocklist,
            startedAt: Date.now.addingTimeInterval(-3600),
            duration: 60
        )
        context.insert(oneShot)
        try context.save()
        XCTAssertFalse(lockdown.isLocked(.editBlocklist(blocklist)))
    }

    func testBlocklistUnlockedWhenReferencedByDisabledSchedule() throws {
        let schedule = Schedule(
            name: "Disabled",
            blocklist: blocklist,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        schedule.enabled = false
        context.insert(schedule)
        try context.save()
        XCTAssertFalse(lockdown.isLocked(.editBlocklist(blocklist)))
    }
}

private extension WeekdayMask {
    static func forAppleWeekday(_ weekday: Int) -> WeekdayMask {
        switch weekday {
        case 1: return .sun
        case 2: return .mon
        case 3: return .tue
        case 4: return .wed
        case 5: return .thu
        case 6: return .fri
        case 7: return .sat
        default: return []
        }
    }
}
