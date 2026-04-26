import Foundation
@testable import Brick

final class MockClock: Clock {
    var now: Date

    init(_ initial: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = initial
    }

    func advance(by seconds: TimeInterval) {
        now.addTimeInterval(seconds)
    }

    func set(_ date: Date) {
        now = date
    }
}
