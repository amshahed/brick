import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SwiftData

/// Coordinates DeviceActivity registrations and applies the current union of
/// active schedules' blocklists to the shared ManagedSettingsStore. Runs in
/// both the main app (sync after edits, app foreground) and the extension
/// (on every interval event).
struct ScheduleEngine {
    let context: ModelContext
    let shield: any ShieldApplying
    let center: DeviceActivityCenter

    init(context: ModelContext,
         shield: any ShieldApplying = ShieldManager(),
         center: DeviceActivityCenter = DeviceActivityCenter()) {
        self.context = context
        self.shield = shield
        self.center = center
    }

    struct ActiveSources {
        var schedules: [Schedule] = []
        var oneShots: [OneShotBlock] = []
    }

    /// Resolve every schedule + one-shot block active at `instant` and apply
    /// the union of their blocklist selections. Returns the active sources.
    @discardableResult
    func applyCurrentUnion(at instant: Date = .now) throws -> ActiveSources {
        let schedules = try context.fetch(FetchDescriptor<Schedule>())
        let oneShots = try context.fetch(FetchDescriptor<OneShotBlock>())
        let travelSuspended = try context.fetch(FetchDescriptor<TravelPeriod>())
            .contains { $0.isActive(at: instant) }

        let activeSchedules: [Schedule]
        if travelSuspended {
            activeSchedules = []
        } else {
            activeSchedules = schedules.filter { schedule in
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
        }
        let activeOneShots = oneShots.filter { $0.startedAt <= instant && instant < $0.expiresAt }

        let scheduleSelections = activeSchedules.compactMap { $0.blocklist?.selection }
        let oneShotSelections = activeOneShots.compactMap { $0.blocklist?.selection }

        // Extension tails: sessions whose source naturally ended but whose
        // effectiveEnd (due to overage extension) hasn't passed yet. Their
        // blocklist still counts toward the union so the shield stays up.
        let openSessions = try context.fetch(
            FetchDescriptor<BlockSession>(predicate: #Predicate { $0.actualEnd == nil })
        )
        let tailSelections: [FamilyActivitySelection] = openSessions.compactMap { session in
            guard session.isInExtensionTail(at: instant) else { return nil }
            return session.schedule?.blocklist?.selection ?? session.oneShotBlock?.blocklist?.selection
        }

        let union = FamilyActivitySelection.union(scheduleSelections + oneShotSelections + tailSelections)

        if union.isEmpty {
            shield.clear()
        } else {
            shield.apply(union: union)
        }
        return ActiveSources(schedules: activeSchedules, oneShots: activeOneShots)
    }

    /// Ensure `BlockSession` rows match currently-active sources: open one
    /// for each active schedule/one-shot that doesn't already have an open
    /// session, and close any open session whose source is no longer active.
    func reconcileBlockSessions(active: ActiveSources, at instant: Date = .now) throws {
        let openSessions = try context.fetch(
            FetchDescriptor<BlockSession>(predicate: #Predicate { $0.actualEnd == nil })
        )
        let preOpenCount = openSessions.count
        let activeScheduleIDs = Set(active.schedules.map(\.id))
        let activeOneShotIDs = Set(active.oneShots.map(\.id))

        for session in openSessions {
            let sourceActive: Bool
            if let schedule = session.schedule {
                sourceActive = activeScheduleIDs.contains(schedule.id)
            } else if let oneShot = session.oneShotBlock {
                sourceActive = activeOneShotIDs.contains(oneShot.id)
            } else {
                sourceActive = false
            }
            let inTail = session.isInExtensionTail(at: instant)
            if !sourceActive && !inTail {
                session.actualEnd = instant
            }
        }

        let hadPriorOpenSession = !openSessions.isEmpty
        let coveredScheduleIDs = Set(openSessions.compactMap { $0.schedule?.id })
        var openedScheduleName: String?
        for schedule in active.schedules where !coveredScheduleIDs.contains(schedule.id) {
            if openedScheduleName == nil { openedScheduleName = schedule.name }
            context.insert(BlockSession(
                schedule: schedule,
                actualStart: instant,
                coldStartEnd: hadPriorOpenSession
                    ? instant
                    : instant.addingTimeInterval(BreakQuotaEngine.coldStartDuration),
                scheduledEnd: ScheduleClock.currentOccurrenceEnd(
                    weekdayMask: schedule.weekdayMask,
                    startMinute: schedule.startMinute,
                    endMinute: schedule.endMinute,
                    startDate: schedule.startDate,
                    endDate: schedule.endDate,
                    at: instant
                )
            ))
        }
        let coveredOneShotIDs = Set(openSessions.compactMap { $0.oneShotBlock?.id })
        for oneShot in active.oneShots where !coveredOneShotIDs.contains(oneShot.id) {
            if openedScheduleName == nil {
                openedScheduleName = oneShot.blocklist?.name ?? "Focus"
            }
            context.insert(BlockSession(
                oneShotBlock: oneShot,
                actualStart: oneShot.startedAt,
                coldStartEnd: hadPriorOpenSession
                    ? oneShot.startedAt
                    : oneShot.startedAt.addingTimeInterval(BreakQuotaEngine.coldStartDuration),
                scheduledEnd: oneShot.expiresAt
            ))
        }
        try context.save()

        let postOpen = try context.fetch(
            FetchDescriptor<BlockSession>(predicate: #Predicate { $0.actualEnd == nil })
        )
        if preOpenCount == 0, !postOpen.isEmpty,
           let name = openedScheduleName {
            NotificationService.shared.blockStarted(scheduleName: name)
        } else if preOpenCount > 0, postOpen.isEmpty {
            let todayTotal = NotificationService.totalBlockedToday(context: context, now: instant)
            NotificationService.shared.blockEnded(todayTotal: todayTotal)
        }
    }

    /// Register a one-off DeviceActivity monitor for a session's extension
    /// tail so the monitor extension wakes up at `effectiveEnd` to reconcile
    /// and drop the shield.
    func registerExtension(for session: BlockSession, at instant: Date = .now) throws {
        let name = DeviceActivityName("brick.extend.\(session.id.uuidString)")
        center.stopMonitoring([name])

        guard let scheduledEnd = session.scheduledEnd,
              let effectiveEnd = session.effectiveEnd,
              effectiveEnd > instant,
              effectiveEnd > scheduledEnd else { return }

        let cal = Calendar.current
        let start = max(instant.addingTimeInterval(1), scheduledEnd)
        guard effectiveEnd > start else { return }
        let startComps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: start
        )
        let endComps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: effectiveEnd
        )
        let dev = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        )
        try center.startMonitoring(name, during: dev)
    }

    /// Drop expired schedules + one-shots, then register DeviceActivity
    /// intervals for everything still live.
    ///
    /// FamilyControls calls (`center.startMonitoring`, `stopMonitoring`)
    /// can block the main thread when auth isn't granted (simulator /
    /// `.notDetermined`). The persistence-side reconcile runs first and
    /// unconditionally so deletes and template-applies are visible in the
    /// UI immediately; only the DA registration is gated on auth, and each
    /// register call is independently try-caught so one bad schedule
    /// doesn't abort the rest. (#22)
    func sync() throws {
        let schedules = try context.fetch(FetchDescriptor<Schedule>())
        for schedule in schedules where schedule.isExpired && schedule.enabled {
            schedule.enabled = false
        }

        let oneShots = try context.fetch(FetchDescriptor<OneShotBlock>())
        let now = Date.now
        let active = try applyCurrentUnion(at: now)
        try reconcileBlockSessions(active: active, at: now)

        for expired in oneShots where expired.expiresAt <= now {
            context.delete(expired)
        }
        try context.save()

        // Skip the DeviceActivity registration entirely if FamilyControls
        // hasn't been authorized. The persistence side already settled
        // above; the user can re-grant auth later and a future sync will
        // re-register everything.
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            return
        }

        center.stopMonitoring()

        for schedule in schedules where schedule.enabled && !schedule.isExpired {
            do { try register(schedule) } catch {
                print("[Brick] sync: register schedule \(schedule.name) failed: \(error)")
            }
        }
        for oneShot in oneShots where oneShot.expiresAt > now {
            do { try register(oneShot) } catch {
                print("[Brick] sync: register one-shot failed: \(error)")
            }
        }
    }

    /// Start a new one-shot: insert, register, and recompute. DA register
    /// is best-effort — the one-shot still persists and counts toward the
    /// active union even if registration fails.
    func start(oneShot: OneShotBlock) throws {
        context.insert(oneShot)
        try context.save()
        if AuthorizationCenter.shared.authorizationStatus == .approved {
            do { try register(oneShot) } catch {
                print("[Brick] start oneShot: register failed: \(error)")
            }
        }
        let active = try applyCurrentUnion()
        try reconcileBlockSessions(active: active)
    }

    private func register(_ schedule: Schedule) throws {
        let wraps = schedule.startMinute >= schedule.endMinute
        let (sh, sm) = ScheduleClock.components(from: schedule.startMinute)
        let (eh, em) = ScheduleClock.components(from: schedule.endMinute)

        for (_, _, mask, appleWeekday) in WeekdayMask.orderedWeekdays
            where schedule.weekdayMask.contains(mask) {

            if wraps {
                // pre-midnight segment: startTime..23:59 on this weekday
                try schedule.register(
                    on: center,
                    name: ActivityNaming.name(scheduleID: schedule.id, appleWeekday: appleWeekday, dayKey: "pre"),
                    start: DateComponents(hour: sh, minute: sm, weekday: appleWeekday),
                    end: DateComponents(hour: 23, minute: 59, weekday: appleWeekday)
                )
                // post-midnight segment: 00:00..endTime on next weekday
                let nextWeekday = appleWeekday == 7 ? 1 : appleWeekday + 1
                try schedule.register(
                    on: center,
                    name: ActivityNaming.name(scheduleID: schedule.id, appleWeekday: appleWeekday, dayKey: "post"),
                    start: DateComponents(hour: 0, minute: 0, weekday: nextWeekday),
                    end: DateComponents(hour: eh, minute: em, weekday: nextWeekday)
                )
            } else {
                try schedule.register(
                    on: center,
                    name: ActivityNaming.name(scheduleID: schedule.id, appleWeekday: appleWeekday),
                    start: DateComponents(hour: sh, minute: sm, weekday: appleWeekday),
                    end: DateComponents(hour: eh, minute: em, weekday: appleWeekday)
                )
            }
        }
    }
}

extension ScheduleEngine {
    /// Register (or re-register) the one-off monitor that fires at the end of
    /// a dated travel period so the engine naturally re-evaluates schedules.
    /// No-ops for toggle-mode periods or periods whose `endDate` is in the past.
    func registerTravelEndReminder(_ period: TravelPeriod) throws {
        let name = DeviceActivityName("brick.travel.\(period.id.uuidString)")
        center.stopMonitoring([name])
        guard let endDate = period.endDate, endDate > .now else { return }
        let cal = Calendar.current
        let start = max(Date.now.addingTimeInterval(1), period.startDate)
        let startComps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: start
        )
        let endComps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: endDate
        )
        try center.startMonitoring(name, during: DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        ))
    }
}

private extension ScheduleEngine {
    func register(_ oneShot: OneShotBlock) throws {
        let cal = Calendar.current
        let startComps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: oneShot.startedAt
        )
        let endComps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: oneShot.expiresAt
        )
        let dev = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        )
        let name = DeviceActivityName("brick.oneshot.\(oneShot.id.uuidString)")
        try center.startMonitoring(name, during: dev)
    }
}

private extension Schedule {
    func register(
        on center: DeviceActivityCenter,
        name: DeviceActivityName,
        start: DateComponents,
        end: DateComponents
    ) throws {
        let dev = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )
        try center.startMonitoring(name, during: dev)
    }
}
