import FamilyControls
import SwiftData
import SwiftUI

@main
struct BrickApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var intentInbox = BreakIntentInbox()
    @StateObject private var breakController: BreakSessionController

    init() {
        // UI-test reset MUST run before the model container is touched —
        // Self.sharedModelContainer is a static initializer and opening the
        // store creates the SQLite file we want to clean.
        Self.applyUITestPreContainerFlags()

        // Apply persisted debug-timing preference (DEBUG builds only).
        BreakQuotaEngine.applyDebugTimings(
            UserDefaults.standard.bool(forKey: BreakQuotaEngine.debugFastTimingsKey)
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
        let controller = BreakSessionController(
            context: Self.sharedModelContainer.mainContext
        )
        _breakController = StateObject(wrappedValue: controller)

        // After the container is up, honor flags that need to write seed
        // state (e.g. pre-install a passcode for tests that drive the gate).
        Self.applyUITestPostContainerFlags(
            context: Self.sharedModelContainer.mainContext
        )
    }

    /// Pre-container UI-test flags. Runs before SQLite is opened.
    /// - `--ui-test-reset-store`: deletes the SQLite store + clears the
    ///   onboarding UserDefaults backstop.
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
        }
        if args.contains("--ui-test-skip-onboarding") {
            UserDefaults.standard.set(
                true,
                forKey: AppSettingsStore.onboardingCompletedDefaultsKey
            )
        }
    }

    /// Delete rows whose load-bearing relationships are nil — leftover
    /// state from a prior crash mid-cascade-delete. Without this, the
    /// next access to `schedule.blocklist?` traps with SwiftData's
    /// "model instance was invalidated" fatal error. (#24)
    private static func cleanUpOrphanedRows(context: ModelContext) {
        do {
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
