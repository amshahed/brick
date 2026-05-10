import FamilyControls
import Foundation
import ManagedSettings
import SwiftData
import XCTest
@testable import Brick

@MainActor
final class OverageExtensionTests: XCTestCase {
    var clock: MockClock!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        clock = MockClock()
        context = try InMemoryStore.make()
    }

    private func makeSchedule(name: String) -> Schedule {
        Schedule(
            name: name,
            blocklist: nil,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
    }

    // MARK: - Overage clamping at hard cap

    func testOverageClampsAtHardCap() throws {
        let session = BlockSession(
            actualStart: clock.now.addingTimeInterval(-2 * 3600),
            coldStartEnd: clock.now.addingTimeInterval(-2 * 3600),
            overageTime: 14 * 60,
            extensionApplied: 28 * 60
        )
        context.insert(session)
        try context.save()

        let engine = BreakQuotaEngine(context: context, clock: clock)
        // Start a 3-min overage break; only 1 min of allowance left.
        let record = try engine.startBreak(
            appTokenData: Data([0x01]),
            plannedDuration: 3 * 60,
            isOverage: true
        )
        clock.advance(by: 3 * 60)
        try engine.endBreak(record)

        XCTAssertEqual(session.overageTime, BreakQuotaEngine.overageHardCap, accuracy: 0.001)
        XCTAssertEqual(
            session.extensionApplied,
            BreakQuotaEngine.overageHardCap * BreakQuotaEngine.overagePenaltyMultiplier,
            accuracy: 0.001
        )
        XCTAssertEqual(try engine.canStartBreak(), .overageLockout)
    }

    // MARK: - Extension tail keeps session open

    func testReconcileKeepsSessionOpenInExtensionTail() throws {
        let schedule = makeSchedule(name: "A")
        context.insert(schedule)

        // Session whose natural end was 30s ago, but 2 min of extension remain.
        let scheduledEnd = clock.now.addingTimeInterval(-30)
        let session = BlockSession(
            schedule: schedule,
            actualStart: clock.now.addingTimeInterval(-30 * 60),
            coldStartEnd: clock.now.addingTimeInterval(-30 * 60),
            scheduledEnd: scheduledEnd,
            overageTime: 60,
            extensionApplied: 120
        )
        context.insert(session)
        try context.save()

        let engine = ScheduleEngine(context: context)
        // Source is NOT active (we pass empty).
        try engine.reconcileBlockSessions(
            active: .init(schedules: [], oneShots: []),
            at: clock.now
        )
        XCTAssertNil(session.actualEnd, "Session in extension tail should stay open")

        // Jump past effectiveEnd → session closes.
        let future = scheduledEnd.addingTimeInterval(120 + 1)
        try engine.reconcileBlockSessions(
            active: .init(schedules: [], oneShots: []),
            at: future
        )
        XCTAssertEqual(session.actualEnd, future)
    }

    // The "union includes extension-tail source" behavior is verified
    // on-device in manual testing — `FamilyActivitySelection` requires real
    // `ApplicationToken`s from `FamilyActivityPicker` to be non-empty, and
    // those can't be constructed in a simulator unit test. Session-open-in-
    // tail behavior is covered by `testReconcileKeepsSessionOpenInExtensionTail`
    // above.
}
