import Foundation
import UserNotifications

enum TravelNudgeScheduler {
    static let dailyID = "brick.travel.daily"
    static let escalatedID = "brick.travel.escalated"

    static func scheduleDaily(startedAt: Date) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        await cancelAll()

        let daily = UNMutableNotificationContent()
        daily.title = "Travel mode is still active"
        daily.body = "Tap to resume your schedules."
        daily.sound = .default
        let dailyTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 9, minute: 0),
            repeats: true
        )
        center.add(UNNotificationRequest(
            identifier: dailyID, content: daily, trigger: dailyTrigger
        )) { _ in }

        let escalated = UNMutableNotificationContent()
        escalated.title = "Travel mode has been active for 7+ days"
        escalated.body = "Your schedules are suspended. Tap to review."
        escalated.sound = .default
        let escalatedFireDate = startedAt.addingTimeInterval(7 * 24 * 3600)
        var comps = Calendar.current.dateComponents(
            [.year, .month, .day], from: escalatedFireDate
        )
        comps.hour = 9
        comps.minute = 0
        let escalatedTrigger = UNCalendarNotificationTrigger(
            dateMatching: comps, repeats: false
        )
        center.add(UNNotificationRequest(
            identifier: escalatedID, content: escalated, trigger: escalatedTrigger
        )) { _ in }
    }

    static func cancelAll() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyID, escalatedID])
    }
}
