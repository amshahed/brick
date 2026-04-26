import Foundation
import SwiftData

@Model
final class Schedule {
    @Attribute(.unique) var id: UUID
    var name: String
    var blocklist: Blocklist?
    var weekdayMaskRaw: Int
    var startMinute: Int
    var endMinute: Int
    var startDate: Date?
    var endDate: Date?
    var repeats: Bool
    var enabled: Bool
    var createdDate: Date

    init(
        id: UUID = UUID(),
        name: String,
        blocklist: Blocklist?,
        weekdayMask: WeekdayMask = .weekdays,
        startMinute: Int,
        endMinute: Int,
        startDate: Date? = nil,
        endDate: Date? = nil,
        repeats: Bool = true,
        enabled: Bool = true,
        createdDate: Date = .now
    ) {
        self.id = id
        self.name = name
        self.blocklist = blocklist
        self.weekdayMaskRaw = weekdayMask.rawValue
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.startDate = startDate
        self.endDate = endDate
        self.repeats = repeats
        self.enabled = enabled
        self.createdDate = createdDate
    }

    var weekdayMask: WeekdayMask {
        get { WeekdayMask(rawValue: weekdayMaskRaw) }
        set { weekdayMaskRaw = newValue.rawValue }
    }

    var isExpired: Bool {
        guard let endDate else { return false }
        return Date.now >= Calendar.current.startOfDay(for: endDate).addingTimeInterval(24 * 3600)
    }

    var isActiveNow: Bool {
        guard enabled else { return false }
        return ScheduleClock.isActive(
            weekdayMask: weekdayMask,
            startMinute: startMinute,
            endMinute: endMinute,
            startDate: startDate,
            endDate: endDate,
            at: .now
        )
    }

    var timeRangeDescription: String {
        let (sh, sm) = ScheduleClock.components(from: startMinute)
        let (eh, em) = ScheduleClock.components(from: endMinute)
        return String(format: "%02d:%02d-%02d:%02d", sh, sm, eh, em)
    }
}
