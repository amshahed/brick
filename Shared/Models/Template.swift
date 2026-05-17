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
    static var all: [Template] {
        var templates: [Template] = [
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
        #if DEBUG
        templates.append(testNowTemplate())
        #endif
        return templates
    }

    static func template(id: String) -> Template? {
        all.first { $0.id == id }
    }

    #if DEBUG
    /// Debug-only template whose window matches the current break-timing
    /// mode: a tight ~10-minute window when "Fast break timings" is on so
    /// the cold-start + quota cycle plays out fast, and a 4-hour window
    /// (now ± 2h) when off so you can leave a long-running block active.
    /// Re-read each access so the window stays current as time advances.
    static func testNowTemplate(now: Date = .now) -> Template {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        let useFast = UserDefaults.standard.bool(
            forKey: BreakQuotaEngine.debugFastTimingsKey
        )
        // Fast: starts 2 min from now, runs 10 minutes (ends T+12). Tuned
        // for quick iteration on the block lifecycle and the 1-min-before-end
        // notification (which fires at T+11). The 5-min-before-start
        // notification is skipped at this offset (lead > window) — that path
        // has already been validated separately. Slow: ±2 hours, the original
        // "block now" behavior.
        let startOffset = useFast ? 2 : -120
        let endOffset = useFast ? 12 : 120
        let start = ((nowMin + startOffset) % 1440 + 1440) % 1440
        let end = ((nowMin + endOffset) % 1440 + 1440) % 1440

        return Template(
            id: "test-now",
            name: useFast ? "Test (T+2 → T+12, 10-min)" : "Test (now ±2h)",
            description: useFast
                ? "Debug only. Starts in 2 min, runs 10 min. Fires the 1-min-before-end notification at T+11. Pair with Settings → Debug → Fast break timings."
                : "Debug only. 4-hour window centered on the current time so blocks fire immediately.",
            startMinute: start,
            endMinute: end,
            weekdayMask: .all,
            requiresDateRange: false
        )
    }
    #endif
}
