import Foundation
import SwiftData
import XCTest
@testable import Brick

@MainActor
final class TemplateApplierTests: XCTestCase {
    var context: ModelContext!
    var applier: TemplateApplier!

    override func setUp() async throws {
        try await super.setUp()
        context = try InMemoryStore.make()
        applier = TemplateApplier(context: context)
    }

    func testApplyCreatesBlocklistAndSchedule() throws {
        let t = try XCTUnwrap(TemplateLibrary.template(id: "morning-focus"))
        let result = try applier.apply(t)
        XCTAssertEqual(result.blocklist.name, "Morning Focus")
        XCTAssertEqual(result.schedule.name, "Morning Focus")
        XCTAssertEqual(result.schedule.startMinute, 6 * 60)
        XCTAssertEqual(result.schedule.endMinute, 10 * 60)
        XCTAssertEqual(result.schedule.weekdayMask, .weekdays)
        XCTAssertNil(result.schedule.startDate)
        XCTAssertNil(result.schedule.endDate)
    }

    func testApplyTwiceReusesExisting() throws {
        let t = try XCTUnwrap(TemplateLibrary.template(id: "deep-work"))
        let first = try applier.apply(t)
        let second = try applier.apply(t)
        XCTAssertEqual(first.blocklist.name, "Deep Work")
        XCTAssertEqual(second.blocklist.name, "Deep Work")
        XCTAssertEqual(
            first.blocklist.persistentModelID,
            second.blocklist.persistentModelID,
            "Re-applying a template must reuse the existing blocklist, not create a duplicate."
        )
        XCTAssertEqual(
            first.schedule.persistentModelID,
            second.schedule.persistentModelID,
            "Re-applying a template must reuse the existing schedule."
        )

        let allBlocklists = try BlocklistStore(context: context).all()
        XCTAssertEqual(allBlocklists.count, 1)
    }

    func testDateBoundedTemplatePreservesDates() throws {
        let t = try XCTUnwrap(TemplateLibrary.template(id: "exam-mode"))
        let start = Date.now
        let end = Date.now.addingTimeInterval(14 * 24 * 3600)
        let result = try applier.apply(t, startDate: start, endDate: end)
        XCTAssertNotNil(result.schedule.startDate)
        XCTAssertNotNil(result.schedule.endDate)
        XCTAssertEqual(result.schedule.startDate!.timeIntervalSince1970,
                       start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(result.schedule.endDate!.timeIntervalSince1970,
                       end.timeIntervalSince1970, accuracy: 1)
    }

    func testNonBoundedTemplateIgnoresDateRange() throws {
        let t = try XCTUnwrap(TemplateLibrary.template(id: "morning-focus"))
        let result = try applier.apply(
            t,
            startDate: .now,
            endDate: .now.addingTimeInterval(3600)
        )
        XCTAssertNil(result.schedule.startDate)
        XCTAssertNil(result.schedule.endDate)
    }
}
