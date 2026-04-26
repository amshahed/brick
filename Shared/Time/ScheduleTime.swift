import Foundation

struct WeekdayMask: OptionSet, Codable, Hashable {
    let rawValue: Int
    static let sun = WeekdayMask(rawValue: 1 << 0)
    static let mon = WeekdayMask(rawValue: 1 << 1)
    static let tue = WeekdayMask(rawValue: 1 << 2)
    static let wed = WeekdayMask(rawValue: 1 << 3)
    static let thu = WeekdayMask(rawValue: 1 << 4)
    static let fri = WeekdayMask(rawValue: 1 << 5)
    static let sat = WeekdayMask(rawValue: 1 << 6)

    static let weekdays: WeekdayMask = [.mon, .tue, .wed, .thu, .fri]
    static let weekends: WeekdayMask = [.sat, .sun]
    static let all: WeekdayMask = [.sun, .mon, .tue, .wed, .thu, .fri, .sat]

    /// Apple's `Calendar.Component.weekday`: 1=Sun ... 7=Sat.
    static let orderedWeekdays: [(label: String, short: String, mask: WeekdayMask, appleWeekday: Int)] = [
        ("Sunday", "Sun", .sun, 1),
        ("Monday", "Mon", .mon, 2),
        ("Tuesday", "Tue", .tue, 3),
        ("Wednesday", "Wed", .wed, 4),
        ("Thursday", "Thu", .thu, 5),
        ("Friday", "Fri", .fri, 6),
        ("Saturday", "Sat", .sat, 7),
    ]

    var shortDescription: String {
        if self == .all { return "Every day" }
        if self == .weekdays { return "Mon-Fri" }
        if self == .weekends { return "Sat-Sun" }
        return Self.orderedWeekdays
            .filter { self.contains($0.mask) }
            .map(\.short)
            .joined(separator: " ")
    }
}

enum ScheduleClock {
    /// Hour-of-day * 60 + minute. 0..1439.
    static func minutes(from hour: Int, minute: Int) -> Int { hour * 60 + minute }

    static func components(from minutes: Int) -> (hour: Int, minute: Int) {
        (minutes / 60, minutes % 60)
    }

    /// Does a schedule that runs `startMinute..<endMinute` on days in `mask`
    /// cover `instant`? Handles wrap-past-midnight (start > end) by treating
    /// the segment before midnight on weekday N as continuing into weekday N+1.
    static func isActive(
        weekdayMask: WeekdayMask,
        startMinute: Int,
        endMinute: Int,
        startDate: Date?,
        endDate: Date?,
        at instant: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if let startDate, instant < calendar.startOfDay(for: startDate) { return false }
        if let endDate, instant >= calendar.startOfDay(for: endDate).addingTimeInterval(24 * 3600) {
            return false
        }

        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: instant)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else {
            return false
        }
        let now = minutes(from: hour, minute: minute)
        let todayMask = mask(for: weekday)
        let yesterdayMask = mask(for: weekday == 1 ? 7 : weekday - 1)

        if startMinute < endMinute {
            return weekdayMask.contains(todayMask) && now >= startMinute && now < endMinute
        } else {
            // Wraps midnight.
            if weekdayMask.contains(todayMask) && now >= startMinute { return true }
            if weekdayMask.contains(yesterdayMask) && now < endMinute { return true }
            return false
        }
    }

    /// End `Date` of the current occurrence if `instant` is inside one, else
    /// `nil`. For non-wrapping schedules the end is `endMinute` today. For
    /// wrap-past-midnight schedules it's `endMinute` today if we're in the
    /// post-midnight half, else `endMinute` tomorrow if we're in the
    /// pre-midnight half.
    static func currentOccurrenceEnd(
        weekdayMask: WeekdayMask,
        startMinute: Int,
        endMinute: Int,
        startDate: Date? = nil,
        endDate: Date? = nil,
        at instant: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard isActive(
            weekdayMask: weekdayMask,
            startMinute: startMinute,
            endMinute: endMinute,
            startDate: startDate,
            endDate: endDate,
            at: instant,
            calendar: calendar
        ) else { return nil }

        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        let now = minutes(from: hour, minute: minute)

        let (eh, em) = components(from: endMinute)
        let todayStart = calendar.startOfDay(for: instant)
        let endToday = calendar.date(
            byAdding: DateComponents(hour: eh, minute: em),
            to: todayStart
        )

        if startMinute < endMinute {
            return endToday
        }
        // Wrap: if we're still in the pre-midnight half, end is tomorrow's
        // endMinute. If we're in the post-midnight half, end is today's.
        if now >= startMinute {
            return calendar.date(byAdding: .day, value: 1, to: endToday ?? todayStart)
        } else {
            return endToday
        }
    }

    private static func mask(for appleWeekday: Int) -> WeekdayMask {
        switch appleWeekday {
        case 1: return .sun
        case 2: return .mon
        case 3: return .tue
        case 4: return .wed
        case 5: return .thu
        case 6: return .fri
        case 7: return .sat
        default: return []
        }
    }
}
