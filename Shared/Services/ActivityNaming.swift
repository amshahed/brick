import DeviceActivity
import Foundation

enum ActivityNaming {
    /// Encode a (schedule id, day key) into a stable DeviceActivityName.
    /// `dayKey` is "pre" for the same-day segment (start..end or start..24:00
    /// when wrapping), and "post" for the wrap-past-midnight segment.
    static func name(scheduleID: UUID, appleWeekday: Int, dayKey: String = "pre") -> DeviceActivityName {
        DeviceActivityName("brick.\(scheduleID.uuidString).\(appleWeekday).\(dayKey)")
    }

    static func parse(_ name: DeviceActivityName) -> (scheduleID: UUID, appleWeekday: Int, dayKey: String)? {
        let parts = name.rawValue.split(separator: ".", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "brick",
              let uuid = UUID(uuidString: String(parts[1])),
              let weekday = Int(parts[2]) else { return nil }
        return (uuid, weekday, String(parts[3]))
    }
}
