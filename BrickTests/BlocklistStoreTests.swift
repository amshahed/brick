import Foundation
import SwiftData
import XCTest
@testable import Brick

/// Covers PRD user story 1 ("named blocklists, reusable groups") and the
/// CRUD acceptance criteria from issue #3 (empty name, duplicate name,
/// rename, cascade-on-delete via referencing schedules).
@MainActor
final class BlocklistStoreTests: XCTestCase {
    var context: ModelContext!
    var store: BlocklistStore!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
        store = BlocklistStore(context: context)
    }

    func testCreatePersistsBlocklist() throws {
        let created = try store.create(name: "Social")
        XCTAssertEqual(created.name, "Social")
        let all = try store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Social")
    }

    func testCreateTrimsWhitespace() throws {
        let created = try store.create(name: "  Deep Work  ")
        XCTAssertEqual(created.name, "Deep Work")
    }

    func testCreateRejectsEmptyName() {
        XCTAssertThrowsError(try store.create(name: "   ")) { error in
            guard case BlocklistStoreError.emptyName = error else {
                return XCTFail("Expected emptyName, got \(error)")
            }
        }
    }

    func testCreateRejectsDuplicateName() throws {
        _ = try store.create(name: "Focus")
        XCTAssertThrowsError(try store.create(name: "Focus")) { error in
            guard case BlocklistStoreError.duplicateName(let name) = error else {
                return XCTFail("Expected duplicateName, got \(error)")
            }
            XCTAssertEqual(name, "Focus")
        }
    }

    func testRenameUpdatesName() throws {
        let blocklist = try store.create(name: "Social")
        try store.rename(blocklist, to: "Distractions")
        XCTAssertEqual(blocklist.name, "Distractions")
    }

    func testRenameToExistingThrows() throws {
        _ = try store.create(name: "A")
        let b = try store.create(name: "B")
        XCTAssertThrowsError(try store.rename(b, to: "A"))
    }

    func testRenameToSameNameIsNoop() throws {
        let blocklist = try store.create(name: "Same")
        XCTAssertNoThrow(try store.rename(blocklist, to: "Same"))
    }

    func testDeleteRemovesBlocklist() throws {
        let blocklist = try store.create(name: "Throwaway")
        try store.delete(blocklist)
        XCTAssertTrue(try store.all().isEmpty)
    }

    /// Per issue #4 deletion guard: deleting a blocklist referenced by a
    /// schedule must throw `referencedBySchedules` unless `cascade` is true.
    /// Cascading must remove the schedule too, so the user doesn't end up
    /// with an orphaned, unenforceable rule.
    func testDeleteThrowsWhenReferencedBySchedule() throws {
        let blocklist = try store.create(name: "Referenced")
        let schedule = Schedule(
            name: "Morning",
            blocklist: blocklist,
            startMinute: 6 * 60,
            endMinute: 10 * 60
        )
        context.insert(schedule)
        try context.save()

        XCTAssertThrowsError(try store.delete(blocklist)) { error in
            guard case BlocklistStoreError.referencedBySchedules(let names) = error else {
                return XCTFail("Expected referencedBySchedules, got \(error)")
            }
            XCTAssertEqual(names, ["Morning"])
        }

        // Cascade clears both.
        try store.delete(blocklist, cascade: true)
        XCTAssertTrue(try store.all().isEmpty)
        let remainingSchedules = try context.fetch(FetchDescriptor<Schedule>())
        XCTAssertTrue(remainingSchedules.isEmpty, "Cascade should remove referencing schedules.")
    }
}
