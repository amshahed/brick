import FamilyControls
import SwiftData
import SwiftUI
import UserNotifications

@main
struct BrickApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var intentInbox = BreakIntentInbox()
    @StateObject private var breakController: BreakSessionController
    @StateObject private var router: AppRouter

    init() {
        // UI-test reset MUST run before the model container is touched —
        // Self.sharedModelContainer is a static initializer and opening the
        // store creates the SQLite file we want to clean.
        Self.applyUITestPreContainerFlags()

        // Apply persisted debug-timing preference (DEBUG builds only). The
        // flag lives in the app-group suite so the DeviceActivityMonitor
        // extension reads the same value — otherwise the extension picks
        // production timings and the cold-start written into a freshly
        // opened BlockSession lags the toggle. (#34)
        BreakQuotaEngine.applyDebugTimings(
            SharedDefaults.shared.bool(forKey: BreakQuotaEngine.debugFastTimingsKey)
        )

        // Defensive cleanup for orphaned rows left over from prior crashes.
        // SwiftData traps when anyone touches `Schedule.blocklist` on an
        // orphan (Schedule whose Blocklist was deleted but Schedule wasn't
        // committed-deleted alongside). Same for one-shots, sessions,
        // break records. Idempotent. (#24)
        Self.cleanUpOrphanedRows(context: Self.sharedModelContainer.mainContext)

        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            } catch {
                print("[Brick] FamilyControls .individual authorization failed: \(error)")
            }
        }
        Task { await NotificationService.shared.requestAuthorization() }

        // Delegate must be set synchronously here, before SwiftUI's body
        // runs, so taps that cold-launch the app are delivered.
        UNUserNotificationCenter.current().delegate = NotificationService.shared

        let controller = BreakSessionController(
            context: Self.sharedModelContainer.mainContext
        )
        _breakController = StateObject(wrappedValue: controller)

        let router = AppRouter()
        _router = StateObject(wrappedValue: router)
        NotificationService.shared.onTap = { route in
            Task { @MainActor in router.handle(route) }
        }

        // After the container is up, honor flags that need to write seed
        // state (e.g. pre-install a passcode for tests that drive the gate).
        Self.applyUITestPostContainerFlags(
            context: Self.sharedModelContainer.mainContext
        )
    }

    /// Pre-container UI-test flags. Runs before SQLite is opened.
    /// - `--ui-test-reset-store`: deletes the SQLite store + clears the
    ///   onboarding UserDefaults backstop + wipes the app-group
    ///   SharedDefaults suite so flags (debug-fast-timings, future shared
    ///   keys) don't leak between runs. (#38)
    /// - `--ui-test-skip-onboarding`: writes the UserDefaults backstop so
    ///   `RootView` routes past onboarding.
    private static func applyUITestPreContainerFlags() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-test-reset-store") {
            try? FileManager.default.removeItem(at: SharedContainer.storeURL)
            let base = SharedContainer.storeURL
            for suffix in ["-shm", "-wal"] {
                let sidecar = base.deletingLastPathComponent()
                    .appendingPathComponent(base.lastPathComponent + suffix)
                try? FileManager.default.removeItem(at: sidecar)
            }
            UserDefaults.standard.removeObject(
                forKey: AppSettingsStore.onboardingCompletedDefaultsKey
            )
            // Clear every key in the app-group suite so persisted flags
            // from a prior test (or a developer session) don't bleed in.
            let suite = SharedDefaults.shared
            for key in suite.dictionaryRepresentation().keys {
                suite.removeObject(forKey: key)
            }
        }
        if args.contains("--ui-test-skip-onboarding") {
            UserDefaults.standard.set(
                true,
                forKey: AppSettingsStore.onboardingCompletedDefaultsKey
            )
        }
        // Pre-seed the debug-fast-timings flag so UI tests can exercise
        // the read-side propagation (Template names, BreakQuotaEngine
        // timings) without having to drive the SwiftUI Toggle directly —
        // iOS 26's XCUITest interaction with custom-binding Toggles is
        // unreliable. (#38)
        if args.contains("--ui-test-fast-timings") {
            SharedDefaults.shared.set(true, forKey: BreakQuotaEngine.debugFastTimingsKey)
        }
    }

    /// Delete rows whose load-bearing relationships are nil OR dangle —
    /// leftover state from a prior crash mid-cascade-delete. Without this,
    /// the next access to `schedule.blocklist?` or `session.schedule?.x`
    /// traps with SwiftData's "model instance was invalidated" fatal error.
    /// (#24, and the BlockSession.schedule-dangling variant.)
    ///
    /// Why the relationships dangle: none of the @Model classes declare
    /// `@Relationship(inverse:)`, so SwiftData has no inverse to walk when
    /// the parent is deleted. The child's relationship column stays pointed
    /// at the gone row, and accessing the resulting faulted stub traps.
    private static func cleanUpOrphanedRows(context: ModelContext) {
        do {
            // Live-ID sets used to detect dangling BlockSession sources.
            // `persistentModelID` is the relationship's FK and is safe to
            // read even on a faulted stub — only snapshot-backed property
            // access traps.
            let liveScheduleIDs = Set(
                try context.fetch(FetchDescriptor<Schedule>())
                    .map(\.persistentModelID)
            )
            let liveOneShotIDs = Set(
                try context.fetch(FetchDescriptor<OneShotBlock>())
                    .map(\.persistentModelID)
            )

            // Schedules whose blocklist relationship is nil.
            let schedules = try context.fetch(FetchDescriptor<Schedule>())
            var removed = 0
            for schedule in schedules where schedule.blocklist == nil {
                context.delete(schedule)
                removed += 1
            }
            // One-shots whose blocklist is gone.
            let oneShots = try context.fetch(FetchDescriptor<OneShotBlock>())
            for oneShot in oneShots where oneShot.blocklist == nil {
                context.delete(oneShot)
                removed += 1
            }
            // BlockSessions whose source (schedule or one-shot) row is gone.
            // Compare the relationship's persistentModelID against the live
            // ID set; delete any session whose source can't be resolved.
            let allSessions = try context.fetch(FetchDescriptor<BlockSession>())
            for session in allSessions {
                let scheduleID = session.schedule?.persistentModelID
                let oneShotID = session.oneShotBlock?.persistentModelID
                let scheduleDangling = scheduleID.map { !liveScheduleIDs.contains($0) } ?? false
                let oneShotDangling = oneShotID.map { !liveOneShotIDs.contains($0) } ?? false
                if scheduleDangling || oneShotDangling {
                    context.delete(session)
                    removed += 1
                }
            }
            // Open BlockSessions whose source (schedule or one-shot) is gone.
            let openSessions = try context.fetch(
                FetchDescriptor<BlockSession>(predicate: #Predicate { $0.actualEnd == nil })
            )
            for session in openSessions where session.schedule == nil && session.oneShotBlock == nil {
                session.actualEnd = .now
                removed += 1
            }
            if removed > 0 {
                try context.save()
                print("[Brick] cleaned up \(removed) orphaned row(s) from prior crash state")
            }
        } catch {
            print("[Brick] orphan cleanup failed: \(error)")
        }
    }

    /// Post-container UI-test flags. Runs after SwiftData is open.
    /// - `--ui-test-passcode <CODE>`: inserts an AppSettings with the given
    ///   numeric passcode so tests can drive the passcode gate without going
    ///   through the setup UI.
    /// - `--ui-test-seed-active-schedule`: creates a "Test Block" blocklist
    ///   plus an always-on schedule pointing at it, so the schedule reads
    ///   as active right now. Lets UI tests exercise the active-block
    ///   lockdown gate without waiting for a real schedule window.
    private static func applyUITestPostContainerFlags(context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--ui-test-passcode"), i + 1 < args.count {
            let code = args[i + 1]
            try? AppSettingsStore(context: context)
                .setPasscode(code, mode: .userChosen)
        }
        if args.contains("--ui-test-seed-active-schedule") {
            let blocklist = Blocklist(name: "Test Block")
            context.insert(blocklist)
            let schedule = Schedule(
                name: "Always On",
                blocklist: blocklist,
                weekdayMask: .all,
                startMinute: 0,
                endMinute: 24 * 60 - 1
            )
            context.insert(schedule)
            try? context.save()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
                .environmentObject(breakController)
                .environmentObject(intentInbox)
                .environmentObject(router)
                .onAppear {
                    intentInbox.checkForIntent()
                    // Order matters: `resyncShield()` applies the *full*
                    // union (no break-aware exclusions). `refreshFromStore`
                    // then layers the active break's override on top. If
                    // run in the opposite order, the resync wipes the
                    // override and the user's break appears to end on
                    // every app foreground. (#16)
                    resyncShield()
                    breakController.refreshFromStore()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        intentInbox.checkForIntent()
                        resyncShield()
                        rerollScheduleNotifications()
                        breakController.refreshFromStore()
                    }
                }
                .onOpenURL { url in
                    intentInbox.handle(url: url)
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }

    /// Re-evaluate active schedules + one-shots and apply the resulting
    /// union to ManagedSettings. Self-heals the shield when the system's
    /// view diverges from the user's intended state — e.g., when the user
    /// edits a blocklist mid-block, or returns to the app after Screen
    /// Time was toggled in Settings.
    private func resyncShield() {
        try? ScheduleEngine(context: Self.sharedModelContainer.mainContext)
            .applyCurrentUnion()
    }

    /// Roll forward the schedule start/end notification window. Pending
    /// notifications only cover the next 3 days; calling `sync()` again on
    /// each foreground advances the window so distant occurrences eventually
    /// get scheduled. Best-effort — failures are logged inside `sync()`.
    private func rerollScheduleNotifications() {
        try? ScheduleEngine(context: Self.sharedModelContainer.mainContext).sync()
    }

    static let sharedModelContainer: ModelContainer = {
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
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("[Brick] ModelContainer init failed: \(error)")
        }
    }()
}
