import Foundation
import SwiftData
import XCTest
@testable import Brick

/// Covers `ScheduleStore` CRUD: create / update / setEnabled / delete /
/// `schedulesReferencing`. Also pins down PRD user story 7-style sharing
/// (one blocklist used by multiple schedules).
///
/// The store calls `ScheduleEngine.sync()` after every mutation, which
/// touches `DeviceActivityCenter` — that fails outside FamilyControls
/// entitlements. Tests catch and ignore that throw since we're verifying
/// the SwiftData side, not DA registration.
@MainActor
final class ScheduleStoreTests: XCTestCase {
    var context: ModelContext!
    var blocklists: BlocklistStore!
    var schedules: ScheduleStore!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
        blocklists = BlocklistStore(context: context)
        schedules = ScheduleStore(context: context)
    }

    /// `sync()` throws on missing FamilyControls entitlements; swallow that
    /// while still surfacing real validation errors.
    private func attempt<T>(_ block: () throws -> T) throws -> T? {
        do {
            return try block()
        } catch let storeError as ScheduleStoreError {
            throw storeError
        } catch {
            return nil
        }
    }

    func testCreatePersistsSchedule() throws {
        let blocklist = try blocklists.create(name: "Social")
        _ = try attempt {
            try schedules.create(
                name: "Morning",
                blocklist: blocklist,
                weekdayMask: .weekdays,
                startMinute: 6 * 60,
                endMinute: 10 * 60
            )
        }
        let all = try context.fetch(FetchDescriptor<Schedule>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Morning")
        XCTAssertEqual(all.first?.startMinute, 360)
        XCTAssertEqual(all.first?.endMinute, 600)
    }

    func testCreateRejectsEmptyName() throws {
        let blocklist = try blocklists.create(name: "Social")
        XCTAssertThrowsError(
            try schedules.create(
                name: "   ",
                blocklist: blocklist,
                weekdayMask: .weekdays,
                startMinute: 0,
                endMinute: 60
            )
        )
    }

    func testCreateRejectsZeroDurationWindow() throws {
        let blocklist = try blocklists.create(name: "Social")
        XCTAssertThrowsError(
            try schedules.create(
                name: "Same",
                blocklist: blocklist,
                weekdayMask: .all,
                startMinute: 60,
                endMinute: 60
            )
        )
    }

    /// PRD user story (implicit): a schedule's name, time, weekday, blocklist
    /// reference, and date range can all be edited. `update` rewrites every
    /// field in one shot.
    func testUpdateRewritesAllFields() throws {
        let socialList = try blocklists.create(name: "Social")
        let workList = try blocklists.create(name: "Work")
        _ = try attempt {
            try schedules.create(
                name: "Original",
                blocklist: socialList,
                weekdayMask: .weekdays,
                startMinute: 6 * 60,
                endMinute: 10 * 60
            )
        }
        guard let schedule = try context.fetch(FetchDescriptor<Schedule>()).first else {
            return XCTFail("Schedule should exist after create.")
        }

        _ = try attempt {
            try schedules.update(
                schedule,
                name: "Updated",
                blocklist: workList,
                weekdayMask: .weekends,
                startMinute: 9 * 60,
                endMinute: 17 * 60,
                startDate: nil,
                endDate: nil
            )
        }

        XCTAssertEqual(schedule.name, "Updated")
        XCTAssertEqual(schedule.blocklist?.persistentModelID, workList.persistentModelID)
        XCTAssertEqual(schedule.weekdayMask, .weekends)
        XCTAssertEqual(schedule.startMinute, 9 * 60)
        XCTAssertEqual(schedule.endMinute, 17 * 60)
    }

    func testSetEnabledTogglesField() throws {
        let blocklist = try blocklists.create(name: "Social")
        _ = try attempt {
            try schedules.create(
                name: "S",
                blocklist: blocklist,
                weekdayMask: .all,
                startMinute: 0,
                endMinute: 60
            )
        }
        guard let schedule = try context.fetch(FetchDescriptor<Schedule>()).first else {
            return XCTFail()
        }

        XCTAssertTrue(schedule.enabled)
        _ = try attempt { try schedules.setEnabled(schedule, false) }
        XCTAssertFalse(schedule.enabled)
        _ = try attempt { try schedules.setEnabled(schedule, true) }
        XCTAssertTrue(schedule.enabled)
    }

    func testDeleteRemovesSchedule() throws {
        let blocklist = try blocklists.create(name: "Social")
        _ = try attempt {
            try schedules.create(
                name: "Doomed",
                blocklist: blocklist,
                weekdayMask: .all,
                startMinute: 0,
                endMinute: 60
            )
        }
        guard let schedule = try context.fetch(FetchDescriptor<Schedule>()).first else {
            return XCTFail()
        }

        _ = try attempt { try schedules.delete(schedule) }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Schedule>()).count, 0)
    }

    /// The user's "multiple schedules can use the same blocklist" check.
    /// `schedulesReferencing` is the engine's hook for cascade-delete and
    /// the union compute, so it must return *all* schedules pointing at
    /// the blocklist, not just the first.
    func testMultipleSchedulesCanShareOneBlocklist() throws {
        let shared = try blocklists.create(name: "Social")
        for name in ["Morning", "Evening", "Weekend"] {
            _ = try attempt {
                try schedules.create(
                    name: name,
                    blocklist: shared,
                    weekdayMask: .all,
                    startMinute: 0,
                    endMinute: 60
                )
            }
        }
        let referencing = try schedules.schedulesReferencing(shared)
        XCTAssertEqual(
            referencing.count,
            3,
            "All schedules pointing at a blocklist must be returned."
        )
        XCTAssertEqual(
            Set(referencing.map(\.name)),
            Set(["Morning", "Evening", "Weekend"])
        )
    }
}
