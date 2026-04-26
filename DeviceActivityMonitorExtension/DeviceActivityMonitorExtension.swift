import DeviceActivity
import Foundation
import SwiftData

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        reconcile()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        reconcile()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
    }

    private func reconcile() {
        do {
            let schema = Schema([Blocklist.self, Schedule.self, OneShotBlock.self, BlockSession.self, BreakRecord.self])
            let config = ModelConfiguration(
                schema: schema,
                url: SharedContainer.storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let engine = ScheduleEngine(context: context)
            let active = try engine.applyCurrentUnion()
            try engine.reconcileBlockSessions(active: active)
        } catch {
            print("[Brick.Ext] reconcile failed: \(error)")
        }
    }
}
