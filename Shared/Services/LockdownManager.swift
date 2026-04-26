import Foundation
import SwiftData

enum LockedAction {
    case editBlocklist(Blocklist)
    case deleteBlocklist(Blocklist)
    case disableSchedule(Schedule)
    case deleteSchedule(Schedule)
    case cancelOneShot(OneShotBlock)
}

struct LockdownManager {
    let context: ModelContext

    func isLocked(_ action: LockedAction, at instant: Date = .now) -> Bool {
        switch action {
        case .disableSchedule(let schedule), .deleteSchedule(let schedule):
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
