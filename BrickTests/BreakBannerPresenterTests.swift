import Foundation
import XCTest
@testable import Brick

/// Covers the banner-decision tree extracted from BreakPickerView so the
/// "block ends before quota refreshes" path (and friends) get unit
/// coverage instead of riding on manual on-device checks. (#37)
final class BreakBannerPresenterTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // MARK: - allowed

    func testAllowedWithNoBlockEndPassesThroughQuota() {
        let result = BreakBannerPresenter.banner(
            availability: .allowed(remainingQuota: 8 * 60),
            blockEnd: nil,
            now: now
        )
        XCTAssertEqual(result, .allowed(maxMinutes: 8))
    }

    func testAllowedClampsToBlockRemainingWhenSmaller() {
        // 7 min of block left, 10 min of quota — clamp to 7.
        let result = BreakBannerPresenter.banner(
            availability: .allowed(remainingQuota: 10 * 60),
            blockEnd: now.addingTimeInterval(7 * 60),
            now: now
        )
        XCTAssertEqual(result, .allowed(maxMinutes: 7))
    }

    func testAllowedClampsToQuotaWhenSmaller() {
        // 30 min of block left, 4 min of quota — clamp to 4.
        let result = BreakBannerPresenter.banner(
            availability: .allowed(remainingQuota: 4 * 60),
            blockEnd: now.addingTimeInterval(30 * 60),
            now: now
        )
        XCTAssertEqual(result, .allowed(maxMinutes: 4))
    }

    func testAllowedWithLessThanOneMinuteOfBlockBecomesBlockEnding() {
        // 30 seconds of block left → no useful break.
        let blockEnd = now.addingTimeInterval(30)
        let result = BreakBannerPresenter.banner(
            availability: .allowed(remainingQuota: 10 * 60),
            blockEnd: blockEnd,
            now: now
        )
        XCTAssertEqual(result, .blockEnding(blockEnd: blockEnd))
    }

    // MARK: - quotaExhausted

    func testQuotaExhaustedPassesThroughWhenQuotaRefreshesBeforeBlockEnds() {
        let availableAt = now.addingTimeInterval(5 * 60)
        let result = BreakBannerPresenter.banner(
            availability: .quotaExhausted(availableAt: availableAt),
            blockEnd: now.addingTimeInterval(20 * 60),
            now: now
        )
        XCTAssertEqual(result, .quotaExhausted(availableAt: availableAt))
    }

    func testQuotaExhaustedFlipsToBlockEndingWhenQuotaRefreshesAfterBlockEnds() {
        let blockEnd = now.addingTimeInterval(2 * 60)
        let availableAt = now.addingTimeInterval(5 * 60)
        let result = BreakBannerPresenter.banner(
            availability: .quotaExhausted(availableAt: availableAt),
            blockEnd: blockEnd,
            now: now
        )
        XCTAssertEqual(result, .blockEnding(blockEnd: blockEnd))
    }

    func testQuotaExhaustedWithNoBlockEndPassesThrough() {
        let availableAt = now.addingTimeInterval(5 * 60)
        let result = BreakBannerPresenter.banner(
            availability: .quotaExhausted(availableAt: availableAt),
            blockEnd: nil,
            now: now
        )
        XCTAssertEqual(result, .quotaExhausted(availableAt: availableAt))
    }

    // MARK: - pass-through cases

    func testColdStartPassesThrough() {
        let endsAt = now.addingTimeInterval(60)
        let result = BreakBannerPresenter.banner(
            availability: .coldStart(endsAt: endsAt),
            blockEnd: now.addingTimeInterval(3600),
            now: now
        )
        XCTAssertEqual(result, .coldStart(endsAt: endsAt))
    }

    func testOverageLockoutPassesThrough() {
        let result = BreakBannerPresenter.banner(
            availability: .overageLockout,
            blockEnd: now.addingTimeInterval(60),
            now: now
        )
        XCTAssertEqual(result, .overageLockout)
    }

    func testNoActiveBlockPassesThrough() {
        let result = BreakBannerPresenter.banner(
            availability: .noActiveBlock,
            blockEnd: nil,
            now: now
        )
        XCTAssertEqual(result, .noActiveBlock)
    }
}
