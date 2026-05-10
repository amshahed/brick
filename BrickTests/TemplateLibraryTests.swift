import Foundation
import XCTest
@testable import Brick

final class TemplateLibraryTests: XCTestCase {
    func testHasFiveTemplates() {
        #if DEBUG
        XCTAssertEqual(TemplateLibrary.all.count, 6)
        #else
        XCTAssertEqual(TemplateLibrary.all.count, 5)
        #endif
    }

    func testTemplateIDsAreUnique() {
        let ids = TemplateLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testMorningFocusParams() throws {
        let t = try XCTUnwrap(TemplateLibrary.template(id: "morning-focus"))
        XCTAssertEqual(t.startMinute, 6 * 60)
        XCTAssertEqual(t.endMinute, 10 * 60)
        XCTAssertEqual(t.weekdayMask, .weekdays)
        XCTAssertFalse(t.requiresDateRange)
    }

    func testNightWindDownWraps() throws {
        let t = try XCTUnwrap(TemplateLibrary.template(id: "night-wind-down"))
        XCTAssertTrue(t.wraps, "22:00–07:00 should register as wrap-past-midnight.")
    }

    func testExamModeRequiresDateRange() throws {
        let t = try XCTUnwrap(TemplateLibrary.template(id: "exam-mode"))
        XCTAssertTrue(t.requiresDateRange)
    }

    func testVacationLightRequiresDateRange() throws {
        let t = try XCTUnwrap(TemplateLibrary.template(id: "vacation-light"))
        XCTAssertTrue(t.requiresDateRange)
    }
}
