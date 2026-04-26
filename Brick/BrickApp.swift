import FamilyControls
import SwiftData
import SwiftUI

@main
struct BrickApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var intentInbox = BreakIntentInbox()
    @StateObject private var breakController: BreakSessionController

    init() {
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .child)
            } catch {
                print("[Brick] FamilyControls .child authorization failed: \(error)")
            }
        }
        Task { await NotificationService.shared.requestAuthorization() }
        let controller = BreakSessionController(
            context: Self.sharedModelContainer.mainContext
        )
        _breakController = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(breakController)
                .environmentObject(intentInbox)
                .onAppear {
                    intentInbox.checkForIntent()
                    breakController.refreshFromStore()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        intentInbox.checkForIntent()
                        breakController.refreshFromStore()
                    }
                }
                .onOpenURL { url in
                    intentInbox.handle(url: url)
                }
        }
        .modelContainer(Self.sharedModelContainer)
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
