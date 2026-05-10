import Foundation
import SwiftData
import XCTest
@testable import Brick

/// Covers PRD user stories 6 ("start a one-shot block now") and 7
/// ("uses an existing blocklist"). The cancel path and lifecycle.
///
/// Note: `OneShotBlockStore.start` runs through `ScheduleEngine.start`
/// which registers with `DeviceActivityCenter` — that needs FamilyControls
/// entitlements unavailable to the test bundle. So we exercise the model
/// + cancel path directly via SwiftData rather than the full store, and
/// reserve the end-to-end "start from Block Now" flow for UI tests.
@MainActor
final class OneShotBlockStoreTests: XCTestCase {
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
    }

    private func insert(blocklist name: String) throws -> Blocklist {
        let blocklist = Blocklist(name: name)
        context.insert(blocklist)
        try context.save()
        return blocklist
    }

    func testNewOneShotIsActiveBeforeExpiry() throws {
        let blocklist = try insert(blocklist: "Social")
        let oneShot = OneShotBlock(blocklist: blocklist, duration: 30 * 60)
        context.insert(oneShot)
        try context.save()

        XCTAssertTrue(oneShot.isActive, "Newly-created one-shot should be active.")
        XCTAssertEqual(
            oneShot.expiresAt.timeIntervalSince(oneShot.startedAt),
            30 * 60,
            accuracy: 1.0
        )
    }

    func testRemainingDecreasesWithDuration() throws {
        let blocklist = try insert(blocklist: "Social")
        let short = OneShotBlock(blocklist: blocklist, duration: 5)
        let long = OneShotBlock(blocklist: blocklist, duration: 60 * 60)
        context.insert(short); context.insert(long)
        try context.save()

        XCTAssertLessThan(short.remaining, long.remaining)
    }

    /// `OneShotBlockStore.cancel` only mutates the model + re-runs the
    /// engine to recompute the union. The model side is what we can verify
    /// in unit-test isolation: cancel must set `expiresAt` in the past so
    /// `isActive` flips to false.
    func testCancelMakesOneShotInactive() throws {
        let blocklist = try insert(blocklist: "Social")
        let oneShot = OneShotBlock(blocklist: blocklist, duration: 60 * 60)
        context.insert(oneShot)
        try context.save()
        XCTAssertTrue(oneShot.isActive)

        // Mirror the store's cancel mutation. The engine recompute is
        // covered separately in ScheduleEngineUnionTests.
        oneShot.expiresAt = .now.addingTimeInterval(-1)
        try context.save()

        XCTAssertFalse(oneShot.isActive)
        XCTAssertLessThan(oneShot.expiresAt, Date.now)
    }

    /// PRD user story 8 — multiple one-shots can stack. Each is its own
    /// row; both contribute to the active set.
    func testMultipleOneShotsCoexist() throws {
        let a = try insert(blocklist: "A")
        let b = try insert(blocklist: "B")
        context.insert(OneShotBlock(blocklist: a, duration: 30 * 60))
        context.insert(OneShotBlock(blocklist: b, duration: 60 * 60))
        try context.save()

        let all = try context.fetch(FetchDescriptor<OneShotBlock>())
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy(\.isActive))
    }
}
