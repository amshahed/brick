import Foundation
import SwiftData
import XCTest
@testable import Brick

@MainActor
final class TravelModeTests: XCTestCase {
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
    }

    // MARK: - TravelPeriod.isActive

    func testToggleTravelActiveNow() {
        let period = TravelPeriod(startDate: .now.addingTimeInterval(-60), endDate: nil)
        XCTAssertTrue(period.isActive())
        XCTAssertFalse(period.isDated)
    }

    func testDatedTravelActiveWithinWindow() {
        let start = Date.now.addingTimeInterval(-3600)
        let end = Date.now.addingTimeInterval(3600)
        let period = TravelPeriod(startDate: start, endDate: end)
        XCTAssertTrue(period.isActive())
        XCTAssertTrue(period.isDated)
    }

    func testDatedTravelInactiveBeforeStart() {
        let start = Date.now.addingTimeInterval(3600)
        let end = Date.now.addingTimeInterval(7200)
        let period = TravelPeriod(startDate: start, endDate: end)
        XCTAssertFalse(period.isActive())
    }

    func testDatedTravelInactiveAfterEnd() {
        let start = Date.now.addingTimeInterval(-7200)
        let end = Date.now.addingTimeInterval(-3600)
        let period = TravelPeriod(startDate: start, endDate: end)
        XCTAssertFalse(period.isActive())
    }

    func testToggleActiveWhenEndDateInFuture() {
        let start = Date.now.addingTimeInterval(-3600)
        let future = Date.now.addingTimeInterval(3600)
        let period = TravelPeriod(startDate: start, endDate: future)
        XCTAssertTrue(period.isActive())
    }

    // MARK: - Travel suspension gate

    /// Mirrors ScheduleEngine's `travelSuspended` gate: when any TravelPeriod is
    /// active at `instant`, schedules are zeroed out while one-shots remain.
    func testTravelSuspensionZeroesSchedulesButNotOneShots() throws {
        let blocklist = Blocklist(name: "B")
        context.insert(blocklist)

        let schedule = Schedule(
            name: "Always",
            blocklist: blocklist,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        context.insert(schedule)

        let oneShot = OneShotBlock(
            blocklist: blocklist,
            startedAt: .now.addingTimeInterval(-60),
            duration: 600
        )
        context.insert(oneShot)

        let travel = TravelPeriod(startDate: .now.addingTimeInterval(-60), endDate: nil)
        context.insert(travel)
        try context.save()

        let now = Date.now
        let travelActive = try context.fetch(FetchDescriptor<TravelPeriod>())
            .contains { $0.isActive(at: now) }
        XCTAssertTrue(travelActive)

        let schedules = try context.fetch(FetchDescriptor<Schedule>())
        let oneShots = try context.fetch(FetchDescriptor<OneShotBlock>())
        let activeSchedules: [Schedule] = travelActive ? [] : schedules.filter { _ in true }
        let activeOneShots = oneShots.filter { $0.startedAt <= now && now < $0.expiresAt }

        XCTAssertTrue(activeSchedules.isEmpty, "Schedules should be suspended during travel.")
        XCTAssertEqual(activeOneShots.count, 1, "One-shots should remain active during travel.")
    }

    func testSchedulesResumeWhenTravelEnded() throws {
        let blocklist = Blocklist(name: "B")
        context.insert(blocklist)

        let travel = TravelPeriod(
            startDate: .now.addingTimeInterval(-7200),
            endDate: .now.addingTimeInterval(-60)
        )
        context.insert(travel)
        try context.save()

        let now = Date.now
        let travelActive = try context.fetch(FetchDescriptor<TravelPeriod>())
            .contains { $0.isActive(at: now) }
        XCTAssertFalse(travelActive, "Travel period with past endDate should not be active.")
    }

    // MARK: - At most one active period invariant

    /// Simulates TravelPeriodStore's `endAnyCurrent` behavior directly on the
    /// context: before inserting a new period, any open/future period's endDate
    /// is set to now, ensuring only one is active at a time.
    func testEndAnyCurrentCollapsesMultipleOpenPeriods() throws {
        let first = TravelPeriod(
            startDate: .now.addingTimeInterval(-3600),
            endDate: nil
        )
        let second = TravelPeriod(
            startDate: .now.addingTimeInterval(-60),
            endDate: .now.addingTimeInterval(3600)
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let now = Date.now
        let existing = try context.fetch(FetchDescriptor<TravelPeriod>())
        for period in existing where period.isActive(at: now) || (period.endDate ?? .distantFuture) > now {
            period.endDate = now
        }
        try context.save()

        let future = now.addingTimeInterval(1)
        let stillActive = try context.fetch(FetchDescriptor<TravelPeriod>())
            .filter { $0.isActive(at: future) }
        XCTAssertTrue(stillActive.isEmpty)
    }
}
