import Foundation
import SwiftData

enum LockedAction {
    case editBlocklist(Blocklist)
    case deleteBlocklist(Blocklist)
    case disableSchedule(Schedule)
    case deleteSchedule(Schedule)
    /// Editing the load-bearing fields of a schedule (blocklist reference,
    /// weekday mask, time window, date bounds) while it's actively running.
    /// Renaming a schedule is *not* covered by this lock — the name doesn't
    /// affect what's blocked right now. PRD story 31 keeps the lockdown
    /// minimal; we only gate fields that change current enforcement.
    case editScheduleFields(Schedule)
    case cancelOneShot(OneShotBlock)
}

struct LockdownManager {
    let context: ModelContext

    func isLocked(_ action: LockedAction, at instant: Date = .now) -> Bool {
        switch action {
        case .disableSchedule(let schedule),
             .deleteSchedule(let schedule),
             .editScheduleFields(let schedule):
            return isScheduleActive(schedule, at: instant)
        case .cancelOneShot(let oneShot):
            return oneShot.startedAt <= instant && instant < oneShot.expiresAt
        case .editBlocklist(let blocklist), .deleteBlocklist(let blocklist):
            return isBlocklistEnforced(blocklist, at: instant)
        }
    }

    private func isScheduleActive(_ schedule: Schedule, at instant: Date) -> Bool {
        guard schedule.enabled, !schedule.isExpired else { return false }
        return ScheduleClock.isActive(
            weekdayMask: schedule.weekdayMask,
            startMinute: schedule.startMinute,
            endMinute: schedule.endMinute,
            startDate: schedule.startDate,
            endDate: schedule.endDate,
            at: instant
        )
    }

    private func isBlocklistEnforced(_ blocklist: Blocklist, at instant: Date) -> Bool {
        let blocklistID = blocklist.persistentModelID
        let schedules = (try? context.fetch(FetchDescriptor<Schedule>())) ?? []
        if schedules.contains(where: {
            $0.blocklist?.persistentModelID == blocklistID && isScheduleActive($0, at: instant)
        }) {
            return true
        }
        let oneShots = (try? context.fetch(FetchDescriptor<OneShotBlock>())) ?? []
        return oneShots.contains {
            $0.blocklist?.persistentModelID == blocklistID
                && $0.startedAt <= instant
                && instant < $0.expiresAt
        }
    }
}
