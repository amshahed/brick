import Foundation

/// A starter template that scaffolds a named blocklist + schedule. Templates
/// have no persistence of their own — they are factories used by the
/// onboarding flow and the "Start from template" entry in the blocklists tab.
struct Template: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let startMinute: Int
    let endMinute: Int
    let weekdayMask: WeekdayMask
    let requiresDateRange: Bool

    var wraps: Bool { startMinute >= endMinute }
}

enum TemplateLibrary {
    static let all: [Template] = [
        Template(
            id: "morning-focus",
            name: "Morning Focus",
            description: "Block distractions 6–10 AM on weekdays.",
            startMinute: 6 * 60,
            endMinute: 10 * 60,
            weekdayMask: .weekdays,
            requiresDateRange: false
        ),
        Template(
            id: "deep-work",
            name: "Deep Work",
            description: "9 AM–5 PM weekdays — hold the line through the workday.",
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            weekdayMask: .weekdays,
            requiresDateRange: false
        ),
        Template(
            id: "night-wind-down",
            name: "Night Wind-Down",
            description: "10 PM–7 AM daily — protect sleep.",
            startMinute: 22 * 60,
            endMinute: 7 * 60,
            weekdayMask: .all,
            requiresDateRange: false
        ),
        Template(
            id: "exam-mode",
            name: "Exam Mode",
            description: "8 AM–10 PM daily for a bounded period. Pick the date range.",
            startMinute: 8 * 60,
            endMinute: 22 * 60,
            weekdayMask: .all,
            requiresDateRange: true
        ),
        Template(
            id: "vacation-light",
            name: "Vacation Light",
            description: "10 AM–8 PM daily for a bounded trip.",
            startMinute: 10 * 60,
            endMinute: 20 * 60,
            weekdayMask: .all,
            requiresDateRange: true
        ),
    ]

    static func template(id: String) -> Template? {
        all.first { $0.id == id }
    }
}
