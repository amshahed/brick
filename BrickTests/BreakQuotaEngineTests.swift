import Foundation
import SwiftData
import XCTest
@testable import Brick

@MainActor
final class BreakQuotaEngineTests: XCTestCase {
    var clock: MockClock!
    var context: ModelContext!
    var session: BlockSession!
    var engine: BreakQuotaEngine!

    override func setUp() async throws {
        try await super.setUp()
        clock = MockClock()
        context = try InMemoryStore.make()
        session = BlockSession(
            actualStart: clock.now.addingTimeInterval(-2 * 3600),
            coldStartEnd: clock.now.addingTimeInterval(-2 * 3600)
        )
        context.insert(session)
        try context.save()
        engine = BreakQuotaEngine(context: context, clock: clock)
    }

    private func insertClosedBreak(startOffset: TimeInterval, duration: TimeInterval, isOverage: Bool = false) throws {
        let start = clock.now.addingTimeInterval(startOffset)
        let record = BreakRecord(
            blockSession: session,
            startTime: start,
            endTime: start.addingTimeInterval(duration),
            appTokenData: Data(),
            wasOverage: isOverage
        )
        context.insert(record)
        try context.save()
    }

    // MARK: - Rolling window

    func testRollingWindowDecay() throws {
        try insertClosedBreak(startOffset: -45 * 60, duration: 5 * 60)
        try insertClosedBreak(startOffset: -30 * 60, duration: 3 * 60)
        let remaining = try engine.remainingQuota()
        XCTAssertEqual(remaining, (10 - 5 - 3) * 60, accuracy: 0.001)
    }

    func testFullyDecayedBreakOutsideWindow() throws {
        try insertClosedBreak(startOffset: -90 * 60, duration: 5 * 60)
        XCTAssertEqual(try engine.remainingQuota(), 10 * 60, accuracy: 0.001)
    }

    func testWindowBoundaryPartialOverlap() throws {
        // 4-min break from T-62m to T-58m → only 2 min inside the 60-min window.
        try insertClosedBreak(startOffset: -62 * 60, duration: 4 * 60)
        XCTAssertEqual(try engine.remainingQuota(), (10 - 2) * 60, accuracy: 0.001)
    }

    func testCapEnforcement() throws {
        try insertClosedBreak(startOffset: -50 * 60, duration: 4 * 60)
        try insertClosedBreak(startOffset: -30 * 60, duration: 4 * 60)
        try insertClosedBreak(startOffset: -10 * 60, duration: 4 * 60)
        XCTAssertEqual(try engine.remainingQuota(), 0, accuracy: 0.001)
        if case .quotaExhausted = try engine.canStartBreak() {} else {
            XCTFail("Expected quotaExhausted")
        }
    }

    func testActiveBreakCountsElapsed() throws {
        let record = BreakRecord(
            blockSession: session,
            startTime: clock.now.addingTimeInterval(-3 * 60),
            appTokenData: Data()
        )
        context.insert(record)
        try context.save()
        XCTAssertEqual(try engine.remainingQuota(), (10 - 3) * 60, accuracy: 0.001)
    }

    // MARK: - Cold-start

    func testColdStartBlocksBreaks() throws {
        session.actualStart = clock.now
        session.coldStartEnd = clock.now.addingTimeInterval(BreakQuotaEngine.coldStartDuration)
        try context.save()
        guard case .coldStart(let endsAt) = try engine.canStartBreak() else {
            return XCTFail("Expected coldStart")
        }
        XCTAssertEqual(endsAt, session.coldStartEnd)
    }

    func testColdStartExpiresAfter25Min() throws {
        session.actualStart = clock.now.addingTimeInterval(-26 * 60)
        session.coldStartEnd = session.actualStart.addingTimeInterval(BreakQuotaEngine.coldStartDuration)
        try context.save()
        guard case .allowed = try engine.canStartBreak() else {
            return XCTFail("Expected allowed")
        }
    }

    // MARK: - Overage

    func testOverageLockoutAt15Min() throws {
        session.overageTime = 15 * 60
        try context.save()
        XCTAssertEqual(try engine.canStartBreak(), .overageLockout)
        XCTAssertFalse(engine.overageAllowed(for: session))
    }

    func testOverageAllowedBelow15Min() throws {
        session.overageTime = 14 * 60
        try context.save()
        XCTAssertTrue(engine.overageAllowed(for: session))
    }

    // MARK: - No active block

    func testNoActiveBlock() throws {
        session.actualEnd = clock.now
        try context.save()
        XCTAssertEqual(try engine.canStartBreak(), .noActiveBlock)
    }

    // MARK: - Cross-block continuity

    func testQuotaCarriesAcrossBlocks() throws {
        // Close current session, create a new one with a cold-start already expired.
        try insertClosedBreak(startOffset: -20 * 60, duration: 5 * 60)
        session.actualEnd = clock.now.addingTimeInterval(-15 * 60)
        let newSession = BlockSession(
            actualStart: clock.now.addingTimeInterval(-10 * 60),
            coldStartEnd: clock.now.addingTimeInterval(-10 * 60) // overlap — doesn't arm
        )
        context.insert(newSession)
        try context.save()
        XCTAssertEqual(try engine.remainingQuota(), (10 - 5) * 60, accuracy: 0.001)
    }

    // MARK: - start/end lifecycle

    func testStartAndEndBreakUpdatesSessionTotals() throws {
        let record = try engine.startBreak(appTokenData: Data([0x01]))
        clock.advance(by: 4 * 60)
        try engine.endBreak(record)
        XCTAssertEqual(session.totalBreakTime, 4 * 60, accuracy: 0.001)
        XCTAssertEqual(session.overageTime, 0, accuracy: 0.001)
    }

    func testOverageBreakUpdatesExtension() throws {
        let record = try engine.startBreak(appTokenData: Data(), isOverage: true)
        clock.advance(by: 5 * 60)
        try engine.endBreak(record)
        XCTAssertEqual(session.overageTime, 5 * 60, accuracy: 0.001)
        XCTAssertEqual(session.extensionApplied, 10 * 60, accuracy: 0.001)
    }
}
