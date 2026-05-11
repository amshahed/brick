import Foundation
import XCTest
@testable import Brick

/// Regression for issue #17: the BreakPicker's token rows reshuffled on
/// every render because iterating `Set` yields different orders per call.
/// The fix encodes + sorts by byte representation so order is stable.
final class BreakPickerOrderTests: XCTestCase {
    func testOrderIsIdenticalAcrossMultipleCalls() {
        let set: Set<String> = ["zebra", "apple", "mango", "kiwi"]

        let first = BreakPickerView.stableEncodedOrder(set)
        let second = BreakPickerView.stableEncodedOrder(set)
        let third = BreakPickerView.stableEncodedOrder(set)

        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
    }

    func testOrderIsDeterministicForSameInput() {
        // Build the set in two different insertion orders. Set hashing
        // would produce different iteration orders depending on hash
        // seeding — `stableEncodedOrder` should erase that.
        let a = Set(["a", "b", "c", "d", "e"])
        let b = Set(["e", "d", "c", "b", "a"])
        XCTAssertEqual(
            BreakPickerView.stableEncodedOrder(a),
            BreakPickerView.stableEncodedOrder(b),
            "Same elements must produce the same encoded order regardless of how the Set was built."
        )
    }

    func testEmptySetReturnsEmpty() {
        XCTAssertTrue(BreakPickerView.stableEncodedOrder(Set<String>()).isEmpty)
    }
}
