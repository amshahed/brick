import Foundation
import SwiftData

enum ScheduleStoreError: LocalizedError {
    case emptyName
    case missingBlocklist
    case invalidTimeRange

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Name can't be empty."
        case .missingBlocklist: return "Pick a blocklist."
        case .invalidTimeRange: return "Start and end times must differ."
        }
    }
}

struct ScheduleStore {
    let context: ModelContext

    @discardableResult
    func create(
        name: String,
        blocklist: Blocklist,
        weekdayMask: WeekdayMask,
        startMinute: Int,
        endMinute: Int,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) throws -> Schedule {
        try validate(name: name, startMinute: startMinute, endMinute: endMinute)
        let schedule = Schedule(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            blocklist: blocklist,
            weekdayMask: weekdayMask,
            startMinute: startMinute,
            endMinute: endMinute,
            startDate: startDate,
            endDate: endDate
        )
        context.insert(schedule)
        try context.save()
        try ScheduleEngine(context: context).sync()
        return schedule
    }

    func update(
        _ schedule: Schedule,
        name: String,
        blocklist: Blocklist,
        weekdayMask: WeekdayMask,
        startMinute: Int,
        endMinute: Int,
        startDate: Date?,
        endDate: Date?
    ) throws {
        try validate(name: name, startMinute: startMinute, endMinute: endMinute)
        schedule.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.blocklist = blocklist
        schedule.weekdayMask = weekdayMask
        schedule.startMinute = startMinute
        schedule.endMinute = endMinute
        schedule.startDate = startDate
        schedule.endDate = endDate
        try context.save()
        try ScheduleEngine(context: context).sync()
    }

    func setEnabled(_ schedule: Schedule, _ enabled: Bool) throws {
        schedule.enabled = enabled
        try context.save()
        try ScheduleEngine(context: context).sync()
    }

    func delete(_ schedule: Schedule) throws {
        context.delete(schedule)
        try context.save()
        try ScheduleEngine(context: context).sync()
    }

    func schedulesReferencing(_ blocklist: Blocklist) throws -> [Schedule] {
        let blocklistID = blocklist.persistentModelID
        let descriptor = FetchDescriptor<Schedule>(
            predicate: #Predicate { $0.blocklist?.persistentModelID == blocklistID }
        )
        return try context.fetch(descriptor)
    }

    private func validate(name: String, startMinute: Int, endMinute: Int) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScheduleStoreError.emptyName }
        guard startMinute != endMinute else { throw ScheduleStoreError.invalidTimeRange }
    }
}
