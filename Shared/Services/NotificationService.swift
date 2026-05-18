import Foundation
import SwiftData
import UserNotifications

/// Posts UN notifications at key block/break moments and receives taps.
/// Single shared instance; safe to call from the main app or any extension.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    enum Identifier {
        static let blockStarted = "brick.block.started"
        static let blockEnded = "brick.block.ended"
        static let breakRequested = "brick.break.requested"
        static let travelEnding = "brick.travel.ending24h"
        static func breakExpiring(_ id: UUID) -> String { "brick.break.expiring.\(id.uuidString)" }
        static func overage(_ id: UUID) -> String { "brick.overage.\(id.uuidString)" }
        static func blockStarting(scheduleID: UUID, occurrenceStart: Date) -> String {
            "brick.block.starting.\(scheduleID.uuidString).\(Int(occurrenceStart.timeIntervalSince1970))"
        }
        static func blockEnding(scheduleID: UUID, occurrenceEnd: Date) -> String {
            "brick.block.ending.\(scheduleID.uuidString).\(Int(occurrenceEnd.timeIntervalSince1970))"
        }
        static func blockStartingPrefix(scheduleID: UUID) -> String {
            "brick.block.starting.\(scheduleID.uuidString)."
        }
        static func blockEndingPrefix(scheduleID: UUID) -> String {
            "brick.block.ending.\(scheduleID.uuidString)."
        }
    }

    /// Where a notification tap should route the app. Decoded from the
    /// notification's `userInfo` payload by `route(from:)`.
    enum NotificationRoute: Equatable {
        case activeBreak(UUID)
        case schedules
        case travel
    }

    /// Set by the app layer (BrickApp) so taps can drive the AppRouter.
    /// Invoked on the main actor; the closure itself dispatches.
    var onTap: ((NotificationRoute) -> Void)?

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Denial / provisional — UN handles silently from here.
        }
    }

    // MARK: - Immediate

    /// Called from `ScheduleEngine.reconcileBlockSessions` on the
    /// no-active-block → active transition. The reconcile path runs both
    /// in the main app and in `DeviceActivityMonitorExtension.intervalDidStart`,
    /// and the extension process exits within seconds of `intervalDidStart`
    /// returning — so a `trigger: nil` (immediate) request gets dropped
    /// before iOS commits it. A 1-s `UNTimeIntervalNotificationTrigger`
    /// is committed to the system queue synchronously inside `add(_:)`
    /// and survives the extension exit.
    func blockStarted(scheduleName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Block started"
        content.body = "Your \(scheduleName) block started. 25-min cold-start active."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        post(id: Identifier.blockStarted, content: content, trigger: trigger)
    }

    /// Same extension-survival rationale as `blockStarted` — uses a 1-s
    /// trigger instead of `nil` so the notification posts reliably when
    /// reconcile runs from `intervalDidEnd`.
    func blockEnded(todayTotal: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Block ended"
        content.body = "Block ended. \(Self.formatTotalBlocked(todayTotal)) blocked today."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        post(id: Identifier.blockEnded, content: content, trigger: trigger)
    }

    func overageApplied(breakID: UUID, overage: TimeInterval, extensionApplied: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Overage penalty"
        content.body = Self.formatOverage(overage: overage, extensionApplied: extensionApplied)
        content.sound = .default
        post(id: Identifier.overage(breakID), content: content, trigger: nil)
    }

    /// Posted from the shield extension when the user taps "Take a break"
    /// from inside a blocked app. iOS dismisses the shield but cannot deep
    /// link into Brick — so without this nudge the tap appears to do nothing.
    func breakRequested() {
        let content = UNMutableNotificationContent()
        content.title = "Open Brick to take your break"
        content.body = "Tap to choose how long, then we'll let the app through for that window."
        content.sound = .default
        post(id: Identifier.breakRequested, content: content, trigger: nil)
    }

    // MARK: - Time-delayed

    func scheduleBreakExpiring(breakID: UUID, firesAt: Date, now: Date = .now) {
        guard let interval = Self.leadInterval(firesAt: firesAt, lead: 60, now: now) else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Break ending"
        content.body = "1 min left on your break."
        content.sound = .default
        content.userInfo = ["route": "break", "id": breakID.uuidString]
        post(id: Identifier.breakExpiring(breakID), content: content, trigger: trigger)
    }

    func cancelBreakExpiring(breakID: UUID) {
        let id = Identifier.breakExpiring(breakID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func scheduleBlockStarting(
        scheduleID: UUID,
        scheduleName: String,
        startsAt: Date,
        now: Date = .now
    ) {
        guard let interval = Self.leadInterval(firesAt: startsAt, lead: 300, now: now) else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Block starting soon"
        content.body = "\(scheduleName) starts in 5 min."
        content.sound = .default
        content.userInfo = ["route": "schedules"]
        post(
            id: Identifier.blockStarting(scheduleID: scheduleID, occurrenceStart: startsAt),
            content: content,
            trigger: trigger
        )
    }

    func scheduleBlockEnding(
        scheduleID: UUID,
        scheduleName: String,
        endsAt: Date,
        now: Date = .now
    ) {
        guard let interval = Self.leadInterval(firesAt: endsAt, lead: 60, now: now) else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Block ending soon"
        content.body = "\(scheduleName) ends in 1 min."
        content.sound = .default
        content.userInfo = ["route": "schedules"]
        post(
            id: Identifier.blockEnding(scheduleID: scheduleID, occurrenceEnd: endsAt),
            content: content,
            trigger: trigger
        )
    }

    func scheduleTravelEnding(periodEndsAt: Date, now: Date = .now) {
        guard let interval = Self.leadInterval(firesAt: periodEndsAt, lead: 86400, now: now) else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Vacation ending"
        content.body = "Your vacation ends in 24 hours."
        content.sound = .default
        content.userInfo = ["route": "travel"]
        post(id: Identifier.travelEnding, content: content, trigger: trigger)
    }

    func cancelTravelEnding() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.travelEnding])
        center.removeDeliveredNotifications(withIdentifiers: [Identifier.travelEnding])
    }

    /// Cancel any pending or delivered start/end notifications for a schedule.
    /// Uses prefix matching because each occurrence has its own identifier
    /// (epoch-stamped) — so a single cancel removes all queued occurrences.
    /// Async (callback-based) because the UN APIs are; subsequent re-adds
    /// from the caller will go through even if the cancel hasn't completed,
    /// and iOS deduplicates by identifier.
    func cancelBlockNotifications(scheduleID: UUID) {
        let startPrefix = Identifier.blockStartingPrefix(scheduleID: scheduleID)
        let endPrefix = Identifier.blockEndingPrefix(scheduleID: scheduleID)
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter {
                $0.hasPrefix(startPrefix) || $0.hasPrefix(endPrefix)
            }
            if !ids.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
        center.getDeliveredNotifications { notes in
            let ids = notes.map(\.request.identifier).filter {
                $0.hasPrefix(startPrefix) || $0.hasPrefix(endPrefix)
            }
            if !ids.isEmpty {
                self.center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Pure helpers (testable without UN mocking)

    /// Trigger interval for a notification that should fire `lead` seconds
    /// before `firesAt`. Returns nil when the lead pushes the fire date into
    /// the past — callers silently skip.
    static func leadInterval(firesAt: Date, lead: TimeInterval, now: Date) -> TimeInterval? {
        let interval = firesAt.timeIntervalSince(now) - lead
        return interval > 0 ? interval : nil
    }

    /// Decode a notification's userInfo payload into a routing decision.
    /// Pure; called from the delegate `didReceive` and from tests.
    static func route(from userInfo: [AnyHashable: Any]) -> NotificationRoute? {
        guard let kind = userInfo["route"] as? String else { return nil }
        switch kind {
        case "break":
            guard let s = userInfo["id"] as? String, let id = UUID(uuidString: s) else { return nil }
            return .activeBreak(id)
        case "schedules":
            return .schedules
        case "travel":
            return .travel
        default:
            return nil
        }
    }

    // MARK: - Formatting (pure, testable)

    static func formatTotalBlocked(_ total: TimeInterval) -> String {
        let minutes = Int(total.rounded() / 60)
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    static func formatOverage(overage: TimeInterval, extensionApplied: TimeInterval) -> String {
        let overageMin = Int((overage / 60).rounded())
        let extMin = Int((extensionApplied / 60).rounded())
        return "Block extended by \(extMin) min (\(overageMin) min overage × 2)."
    }

    // MARK: - Stats

    /// Sums closed BlockSessions that overlap today's calendar day, clamped
    /// to today's midnight..now window. Open sessions contribute from their
    /// actualStart up to `now`.
    static func totalBlockedToday(context: ModelContext, now: Date = .now) -> TimeInterval {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        let sessions = (try? context.fetch(FetchDescriptor<BlockSession>())) ?? []
        return sessions.reduce(0) { sum, session in
            let sessionEnd = session.actualEnd ?? now
            let overlapStart = max(session.actualStart, startOfDay)
            let overlapEnd = min(sessionEnd, endOfDay)
            guard overlapEnd > overlapStart else { return sum }
            return sum + overlapEnd.timeIntervalSince(overlapStart)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Surface foreground notifications too — the 30s break warning is
        // useless if the user is already inside Brick and never sees it.
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let route = Self.route(from: response.notification.request.content.userInfo) {
            onTap?(route)
        }
        completionHandler()
    }

    // MARK: - Internal

    private func post(id: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}
