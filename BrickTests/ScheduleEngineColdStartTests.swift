import Foundation
import SwiftData
import XCTest
@testable import Brick

@MainActor
final class ScheduleEngineColdStartTests: XCTestCase {
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
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

    func testFirstSessionArmsColdStart() throws {
        let schedule = makeSchedule(name: "A")
        context.insert(schedule)
        try context.save()

        let engine = ScheduleEngine(context: context)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try engine.reconcileBlockSessions(
            active: .init(schedules: [schedule], oneShots: []),
            at: now
        )

        let sessions = try context.fetch(FetchDescriptor<BlockSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(
            sessions[0].coldStartEnd,
            now.addingTimeInterval(BreakQuotaEngine.coldStartDuration)
        )
    }

    func testOverlappingSessionDoesNotReArmColdStart() throws {
        let a = makeSchedule(name: "A")
        let b = makeSchedule(name: "B")
        context.insert(a)
        context.insert(b)
        try context.save()

        let engine = ScheduleEngine(context: context)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // First: arm via schedule A only.
        try engine.reconcileBlockSessions(active: .init(schedules: [a], oneShots: []), at: t0)
        // Second: B joins mid-block — no re-arm on B.
        let t1 = t0.addingTimeInterval(5 * 60)
        try engine.reconcileBlockSessions(active: .init(schedules: [a, b], oneShots: []), at: t1)

        let sessions = try context.fetch(
            FetchDescriptor<BlockSession>(sortBy: [SortDescriptor(\.actualStart)])
        )
        XCTAssertEqual(sessions.count, 2)
        // A: armed fully.
        XCTAssertEqual(sessions[0].coldStartEnd, t0.addingTimeInterval(BreakQuotaEngine.coldStartDuration))
        // B: opened mid-block → coldStartEnd == actualStart (already-warm).
        XCTAssertEqual(sessions[1].coldStartEnd, t1)
        XCTAssertEqual(sessions[1].actualStart, t1)
    }

    func testClosingAllThenOpeningReArms() throws {
        let a = makeSchedule(name: "A")
        context.insert(a)
        try context.save()

        let engine = ScheduleEngine(context: context)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        try engine.reconcileBlockSessions(active: .init(schedules: [a], oneShots: []), at: t0)
        // Nothing active → closes the session.
        let t1 = t0.addingTimeInterval(60 * 60)
        try engine.reconcileBlockSessions(active: .init(schedules: [], oneShots: []), at: t1)
        // Reopen later.
        let t2 = t1.addingTimeInterval(10 * 60)
        try engine.reconcileBlockSessions(active: .init(schedules: [a], oneShots: []), at: t2)

        let sessions = try context.fetch(
            FetchDescriptor<BlockSession>(sortBy: [SortDescriptor(\.actualStart)])
        )
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[1].coldStartEnd, t2.addingTimeInterval(BreakQuotaEngine.coldStartDuration))
    }
}
