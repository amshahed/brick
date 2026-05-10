import FamilyControls
import Foundation
import ManagedSettings
import SwiftData
import XCTest
@testable import Brick

/// Coverage for the category-break path that bridges PRD story 15
/// ("single-app unshield") with the practical reality that some users
/// pick categories only. The whole-category break lifts a category from
/// the shield instead of an individual app token.
@MainActor
final class CategoryBreakTests: XCTestCase {
    private final class RecordingShield: ShieldApplying {
        var lastExceptApps: Set<ApplicationToken> = []
        var lastExceptCategories: Set<ActivityCategoryToken> = []
        var applyCount = 0

        func apply(union selection: FamilyActivitySelection) {
            apply(union: selection, exceptApps: [], exceptCategories: [])
        }
        func apply(
            union selection: FamilyActivitySelection,
            exceptApps: Set<ApplicationToken>,
            exceptCategories: Set<ActivityCategoryToken>
        ) {
            applyCount += 1
            lastExceptApps = exceptApps
            lastExceptCategories = exceptCategories
        }
        func clear() {
            lastExceptApps = []
            lastExceptCategories = []
        }
    }

    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
    }

    /// Existing rows + new rows without an explicit kind read as `.app`,
    /// preserving backward compatibility for the additive schema change.
    func testBreakRecordTargetKindDefaultsToApp() throws {
        let session = BlockSession(actualStart: .now)
        context.insert(session)
        let record = BreakRecord(
            blockSession: session,
            startTime: .now,
            appTokenData: Data()
        )
        context.insert(record)
        try context.save()

        XCTAssertEqual(record.targetKind, .app)
        XCTAssertEqual(record.targetKindRaw, "app")
    }

    /// `BreakQuotaEngine.startBreak` must persist the requested kind so
    /// `refreshFromStore` later decodes the token as the right type.
    func testEngineStartBreakPersistsCategoryKind() throws {
        let blocklist = Blocklist(name: "Social")
        context.insert(blocklist)
        let schedule = Schedule(
            name: "All day",
            blocklist: blocklist,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        context.insert(schedule)
        let session = BlockSession(
            schedule: schedule,
            actualStart: .now.addingTimeInterval(-3600),
            coldStartEnd: .now.addingTimeInterval(-1800)
        )
        context.insert(session)
        try context.save()

        let engine = BreakQuotaEngine(context: context)
        let record = try engine.startBreak(
            appTokenData: Data([0xCA, 0xFE]),
            targetKind: .category,
            plannedDuration: 60
        )

        XCTAssertEqual(record.targetKind, .category)
        XCTAssertEqual(record.targetKindRaw, "category")
        XCTAssertEqual(record.appTokenData, Data([0xCA, 0xFE]))
    }

    /// Category-kind breaks count toward the rolling quota the same as
    /// app-kind breaks. (PRD story 13 — quota is one budget regardless of
    /// what the break unshielded.)
    func testCategoryBreakConsumesQuota() throws {
        let blocklist = Blocklist(name: "Social")
        context.insert(blocklist)
        let schedule = Schedule(
            name: "All day",
            blocklist: blocklist,
            weekdayMask: .all,
            startMinute: 0,
            endMinute: 24 * 60 - 1
        )
        context.insert(schedule)
        let session = BlockSession(
            schedule: schedule,
            actualStart: .now.addingTimeInterval(-3600),
            coldStartEnd: .now.addingTimeInterval(-1800)
        )
        context.insert(session)
        let now = Date.now
        let record = BreakRecord(
            blockSession: session,
            startTime: now.addingTimeInterval(-120),
            endTime: now.addingTimeInterval(-60),
            appTokenData: Data([0xAA]),
            targetKind: .category,
            wasOverage: false,
            plannedDuration: 60
        )
        context.insert(record)
        try context.save()

        let engine = BreakQuotaEngine(context: context)
        let remaining = try engine.remainingQuota(at: now)
        XCTAssertEqual(
            remaining,
            BreakQuotaEngine.quotaCap - 60,
            accuracy: 1.0,
            "A 60s category break must subtract 60s from the rolling quota."
        )
    }

    /// `ShieldManager` (and any conformer) accepts a set of categories to
    /// lift. The passed sets are visible to the conformer — verified with a
    /// recording double since we can't construct real `ActivityCategoryToken`
    /// values in unit tests.
    func testShieldApplyPassesCategoryExceptionsThrough() {
        let shield = RecordingShield()
        let union = FamilyActivitySelection()

        shield.apply(union: union, exceptApps: [], exceptCategories: [])

        XCTAssertEqual(shield.applyCount, 1)
        XCTAssertTrue(shield.lastExceptCategories.isEmpty)
        XCTAssertTrue(shield.lastExceptApps.isEmpty)
    }
}
