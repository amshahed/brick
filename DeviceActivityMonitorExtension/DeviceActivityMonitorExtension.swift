import DeviceActivity
import Foundation
import SwiftData

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        print("[Brick.Ext] intervalDidStart \(activity.rawValue) at \(Date.now)")
        reconcile()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        print("[Brick.Ext] intervalDidEnd \(activity.rawValue) at \(Date.now)")
        reconcile()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
    }

    private func reconcile() {
        // The extension is its own process. `BreakQuotaEngine.coldStartDuration`
        // and friends are process-local statics, so without re-applying the
        // user's debug-timings preference here, a BlockSession opened from
        // a closed-app wake-up is stamped with the production 25-min cold
        // start. Reads from the app-group suite so the toggle is visible
        // across processes. (#34)
        BreakQuotaEngine.applyDebugTimings(
            SharedDefaults.shared.bool(forKey: BreakQuotaEngine.debugFastTimingsKey)
        )
        do {
            // Schema MUST match the main app's container exactly. Mismatched
            // schemas opening the same SQLite file have produced "store
            // couldn't be opened" errors in onboarding saves on real devices.
            let schema = Schema([
                Blocklist.self,
                Schedule.self,
                OneShotBlock.self,
                BlockSession.self,
                BreakRecord.self,
                AppSettings.self,
                TravelPeriod.self,
            ])
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
