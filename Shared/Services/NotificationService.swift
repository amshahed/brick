import Foundation
import SwiftData
import UserNotifications

/// Posts UN notifications at key block/break moments. Single shared instance;
/// safe to call from the main app or any extension process.
final class NotificationService {
    static let shared = NotificationService()

    enum Identifier {
        static let blockStarted = "brick.block.started"
        static let blockEnded = "brick.block.ended"
        static let breakRequested = "brick.break.requested"
        static func breakExpiring(_ id: UUID) -> String { "brick.break.expiring.\(id.uuidString)" }
        static func overage(_ id: UUID) -> String { "brick.overage.\(id.uuidString)" }
    }

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Denial / provisional — UN handles silently from here.
        }
    }

    // MARK: - Immediate

    func blockStarted(scheduleName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Block started"
        content.body = "Your \(scheduleName) block started. 25-min cold-start active."
        content.sound = .default
        post(id: Identifier.blockStarted, content: content, trigger: nil)
    }

    func blockEnded(todayTotal: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Block ended"
        content.body = "Block ended. \(Self.formatTotalBlocked(todayTotal)) blocked today."
        content.sound = .default
        post(id: Identifier.blockEnded, content: content, trigger: nil)
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
        let interval = firesAt.timeIntervalSince(now) - 60
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Break ending"
        content.body = "1 min left on your break."
        content.sound = .default
        post(id: Identifier.breakExpiring(breakID), content: content, trigger: trigger)
    }

    func cancelBreakExpiring(breakID: UUID) {
        let id = Identifier.breakExpiring(breakID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
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

    // MARK: - Internal

    private func post(id: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}
