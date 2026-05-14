import Foundation
import XCTest
@testable import Brick

final class NotificationRouteParsingTests: XCTestCase {

    func testBreakRouteWithUUID() {
        let id = UUID()
        let info: [AnyHashable: Any] = ["route": "break", "id": id.uuidString]
        XCTAssertEqual(NotificationService.route(from: info), .activeBreak(id))
    }

    func testBreakRouteMissingIDReturnsNil() {
        let info: [AnyHashable: Any] = ["route": "break"]
        XCTAssertNil(NotificationService.route(from: info))
    }

    func testBreakRouteMalformedIDReturnsNil() {
        let info: [AnyHashable: Any] = ["route": "break", "id": "not-a-uuid"]
        XCTAssertNil(NotificationService.route(from: info))
    }

    func testSchedulesRoute() {
        let info: [AnyHashable: Any] = ["route": "schedules"]
        XCTAssertEqual(NotificationService.route(from: info), .schedules)
    }

    func testTravelRoute() {
        let info: [AnyHashable: Any] = ["route": "travel"]
        XCTAssertEqual(NotificationService.route(from: info), .travel)
    }

    func testUnknownRouteReturnsNil() {
        let info: [AnyHashable: Any] = ["route": "wat"]
        XCTAssertNil(NotificationService.route(from: info))
    }

    func testEmptyUserInfoReturnsNil() {
        XCTAssertNil(NotificationService.route(from: [:]))
    }
}
