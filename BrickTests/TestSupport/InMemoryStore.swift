import Foundation
import SwiftData
@testable import Brick

enum InMemoryStore {
    @MainActor
    static func make() throws -> ModelContext {
        let schema = Schema([
            Blocklist.self, Schedule.self, OneShotBlock.self,
            BlockSession.self, BreakRecord.self, AppSettings.self,
            TravelPeriod.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
