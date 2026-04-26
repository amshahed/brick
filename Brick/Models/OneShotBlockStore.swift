import Foundation
import SwiftData

struct OneShotBlockStore {
    let context: ModelContext

    @discardableResult
    func start(blocklist: Blocklist, duration: TimeInterval) throws -> OneShotBlock {
        let oneShot = OneShotBlock(blocklist: blocklist, duration: duration)
        try ScheduleEngine(context: context).start(oneShot: oneShot)
        return oneShot
    }

    /// Cancel an active one-shot early. Ends it immediately by expiring it
    /// in the past, then re-runs the engine so the shield/union is recomputed.
    func cancel(_ oneShot: OneShotBlock) throws {
        oneShot.expiresAt = .now.addingTimeInterval(-1)
        try context.save()
        let engine = ScheduleEngine(context: context)
        let active = try engine.applyCurrentUnion()
        try engine.reconcileBlockSessions(active: active)
    }
}
