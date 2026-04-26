import Foundation
import SwiftData

@Model
final class TravelPeriod {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }

    func isActive(at instant: Date = .now) -> Bool {
        guard startDate <= instant else { return false }
        if let endDate { return instant < endDate }
        return true
    }

    var isDated: Bool { endDate != nil }
}
