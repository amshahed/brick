import Foundation
import XCTest
@testable import Brick

final class NotificationLeadIntervalTests: XCTestCase {

    func testReturnsPositiveIntervalWhenAheadOfLead() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firesAt = now.addingTimeInterval(45)
        let interval = try XCTUnwrap(
            NotificationService.leadInterval(firesAt: firesAt, lead: 30, now: now)
        )
        XCTAssertEqual(interval, 15, accuracy: 0.0001)
    }

    func testReturnsNilWhenLeadPushesIntoPast() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firesAt = now.addingTimeInterval(20)
        let interval = NotificationService.leadInterval(firesAt: firesAt, lead: 30, now: now)
        XCTAssertNil(interval)
    }

    func testReturnsNilWhenIntervalIsExactlyZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firesAt = now.addingTimeInterval(30)
        let interval = NotificationService.leadInterval(firesAt: firesAt, lead: 30, now: now)
        // Equal to lead → 0 → not strictly positive → silent skip.
        XCTAssertNil(interval)
    }

    func testFiveMinuteLead() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firesAt = now.addingTimeInterval(600) // 10 min ahead
        let interval = try XCTUnwrap(
            NotificationService.leadInterval(firesAt: firesAt, lead: 300, now: now)
        )
        XCTAssertEqual(interval, 300, accuracy: 0.0001)
    }

    func testTwentyFourHourLead() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firesAt = now.addingTimeInterval(25 * 3600) // 25h ahead
        let interval = try XCTUnwrap(
            NotificationService.leadInterval(firesAt: firesAt, lead: 86400, now: now)
        )
        XCTAssertEqual(interval, 3600, accuracy: 0.0001)
    }
}
