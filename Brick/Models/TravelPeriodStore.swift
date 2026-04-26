import Foundation
import SwiftData

enum TravelPeriodStoreError: LocalizedError {
    case invalidRange

    var errorDescription: String? {
        switch self {
        case .invalidRange: return "End date must be after the start date and in the future."
        }
    }
}

struct TravelPeriodStore {
    let context: ModelContext

    func current() throws -> TravelPeriod? {
        var descriptor = FetchDescriptor<TravelPeriod>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func activeNow(at instant: Date = .now) throws -> TravelPeriod? {
        try context.fetch(FetchDescriptor<TravelPeriod>())
            .first { $0.isActive(at: instant) }
    }

    @discardableResult
    func startToggle() throws -> TravelPeriod {
        try endAnyCurrent()
        let period = TravelPeriod(startDate: .now, endDate: nil)
        context.insert(period)
        try context.save()
        try ScheduleEngine(context: context).sync()
        Task { await TravelNudgeScheduler.scheduleDaily(startedAt: period.startDate) }
        return period
    }

    @discardableResult
    func startDated(from start: Date, to end: Date) throws -> TravelPeriod {
        guard end > start, end > .now else { throw TravelPeriodStoreError.invalidRange }
        try endAnyCurrent()
        let period = TravelPeriod(startDate: start, endDate: end)
        context.insert(period)
        try context.save()
        let engine = ScheduleEngine(context: context)
        try engine.sync()
        try engine.registerTravelEndReminder(period)
        return period
    }

    func end(_ period: TravelPeriod) throws {
        period.endDate = .now
        try context.save()
        let engine = ScheduleEngine(context: context)
        try engine.sync()
        try engine.registerTravelEndReminder(period)
        Task { await TravelNudgeScheduler.cancelAll() }
    }

    private func endAnyCurrent() throws {
        let existing = try context.fetch(FetchDescriptor<TravelPeriod>())
        let now = Date.now
        for period in existing where period.isActive(at: now) || (period.endDate ?? .distantFuture) > now {
            period.endDate = now
        }
        try context.save()
    }
}
