import FamilyControls
import Foundation
import ManagedSettings
import SwiftData
import XCTest
@testable import Brick

/// Covers PRD user stories 8 ("one-shots layer on top of scheduled
/// blocks"), 9 ("one-shot apps stay shielded if the schedule ends
/// first"), and 10 ("overlapping schedules union their blocklists").
///
/// We use a `RecordingShield` injected into `ScheduleEngine` and snapshot
/// the unions it sees — that exercises the same code path that drives the
/// real `ManagedSettingsStore` without needing FamilyControls entitlements.
@MainActor
final class ScheduleEngineUnionTests: XCTestCase {
    fileprivate final class RecordingShield: ShieldApplying {
        var lastUnion: FamilyActivitySelection?
        var clearCount = 0

        func apply(union selection: FamilyActivitySelection) { lastUnion = selection }
        func apply(
            union selection: FamilyActivitySelection,
            exceptApps: Set<ApplicationToken>,
            exceptCategories: Set<ActivityCategoryToken>
        ) {
            lastUnion = selection
        }
        func clear() { clearCount += 1; lastUnion = nil }
    }

    var context: ModelContext!
    fileprivate var shield: RecordingShield!
    var engine: ScheduleEngine!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
        shield = RecordingShield()
        engine = ScheduleEngine(context: context, shield: shield)
    }

    /// Build a schedule that's active right now (covers today's weekday +
    /// a wide enough window around the clock-of-day) so engine logic kicks
    /// in without needing time mocking.
    private func makeAlwaysOnSchedule(name: String, blocklist: Blocklist) -> Schedule {
        Schedule(
            name: name,
            blocklist: blocklist,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
    }

    func testOverlappingSchedulesUnionBlocklists() throws {
        let a = Blocklist(name: "Social")
        let b = Blocklist(name: "News")
        context.insert(a); context.insert(b)
        let schedA = makeAlwaysOnSchedule(name: "A", blocklist: a)
        let schedB = makeAlwaysOnSchedule(name: "B", blocklist: b)
        context.insert(schedA); context.insert(schedB)
        try context.save()

        let active = try engine.applyCurrentUnion()

        XCTAssertEqual(
            active.schedules.count,
            2,
            "Both overlapping schedules must contribute to the active set."
        )
        // We can't assert on shield.lastUnion because the test's blocklists
        // have empty FamilyActivitySelections (ApplicationToken isn't
        // constructible from test code), so the union resolves to empty
        // and the engine takes the `clear` branch. The semantic union
        // assertion lives in `active.schedules.count` above.
    }

    /// A one-shot referencing a different blocklist runs alongside an
    /// active schedule. Both contribute to the union.
    func testOneShotAndScheduleBothActiveCountInUnion() throws {
        let scheduleList = Blocklist(name: "Sched")
        let oneShotList = Blocklist(name: "OneShot")
        context.insert(scheduleList); context.insert(oneShotList)
        let schedule = makeAlwaysOnSchedule(name: "Sched", blocklist: scheduleList)
        context.insert(schedule)
        let oneShot = OneShotBlock(blocklist: oneShotList, duration: 30 * 60)
        context.insert(oneShot)
        try context.save()

        let active = try engine.applyCurrentUnion()

        XCTAssertEqual(active.schedules.count, 1)
        XCTAssertEqual(active.oneShots.count, 1)
    }

    /// PRD user story 9 — even after the scheduled source ends, an active
    /// one-shot must keep contributing to the union.
    func testOneShotSurvivesScheduleEnd() throws {
        let scheduleList = Blocklist(name: "Sched")
        let oneShotList = Blocklist(name: "OneShot")
        context.insert(scheduleList); context.insert(oneShotList)

        // Schedule expired (endDate in the past) so it should NOT be active.
        let expiredSchedule = Schedule(
            name: "Expired",
            blocklist: scheduleList,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1,
            endDate: Date.now.addingTimeInterval(-2 * 24 * 3600)
        )
        context.insert(expiredSchedule)
        let oneShot = OneShotBlock(blocklist: oneShotList, duration: 60 * 60)
        context.insert(oneShot)
        try context.save()

        let active = try engine.applyCurrentUnion()

        XCTAssertTrue(
            active.schedules.isEmpty,
            "Expired schedule should drop out of the active set."
        )
        XCTAssertEqual(active.oneShots.count, 1, "One-shot must remain active.")
    }

    /// Once nothing is active (schedule expired, one-shot expired), the
    /// engine clears the shield. Pins down the cleanup half of story 9.
    func testNothingActiveClearsShield() throws {
        let blocklist = Blocklist(name: "X")
        context.insert(blocklist)
        let expired = Schedule(
            name: "Expired",
            blocklist: blocklist,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1,
            endDate: Date.now.addingTimeInterval(-2 * 24 * 3600)
        )
        context.insert(expired)
        try context.save()

        _ = try engine.applyCurrentUnion()

        XCTAssertNil(shield.lastUnion)
        XCTAssertEqual(shield.clearCount, 1)
    }
}
