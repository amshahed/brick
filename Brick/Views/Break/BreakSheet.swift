import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

/// Root of the break flow. Presents the picker, the overage ritual, or the
/// active-break view based on the controller's state. Accepts an optional
/// preselected app from the shield-action intent.
struct BreakSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var controller: BreakSessionController
    @Query private var schedules: [Schedule]
    @Query private var oneShots: [OneShotBlock]

    let preselectedTokenData: Data?

    @State private var showingOverage = false
    @State private var overageRemaining: TimeInterval = 0
    @State private var overageBlockedTokens: [Data] = []

    var body: some View {
        NavigationStack {
            Group {
                if let active = controller.active {
                    ActiveBreakView(active: active) {
                        controller.endEarly()
                        dismiss()
                    }
                } else {
                    BreakPickerView(
                        preselectedTokenData: preselectedTokenData,
                        onStart: { token, duration in
                            do {
                                try controller.start(app: token, duration: duration)
                            } catch {
                                print("[Brick] start break failed: \(error)")
                            }
                        },
                        onOverride: { openOverage() },
                        onCancel: { dismiss() }
                    )
                }
            }
            .navigationDestination(isPresented: $showingOverage) {
                OverageRitualView(
                    preselectedTokenData: preselectedTokenData,
                    blockedTokens: overageBlockedTokens,
                    remainingOverage: overageRemaining,
                    onConfirm: { token, duration in
                        do {
                            try controller.start(app: token, duration: duration, isOverage: true)
                            showingOverage = false
                        } catch {
                            print("[Brick] start overage break failed: \(error)")
                        }
                    },
                    onCancel: { showingOverage = false }
                )
            }
            .onChange(of: controller.active == nil) { _, becameInactive in
                if becameInactive && controller.active == nil {
                    dismiss()
                }
            }
        }
    }

    private func openOverage() {
        let now = Date.now
        let activeSchedules = schedules.filter(\.enabled).filter { schedule in
            ScheduleClock.isActive(
                weekdayMask: schedule.weekdayMask,
                startMinute: schedule.startMinute,
                endMinute: schedule.endMinute,
                startDate: schedule.startDate,
                endDate: schedule.endDate,
                at: now
            )
        }
        let activeOneShots = oneShots.filter { $0.startedAt <= now && now < $0.expiresAt }
        let selections = activeSchedules.compactMap { $0.blocklist?.selection }
            + activeOneShots.compactMap { $0.blocklist?.selection }
        let union = FamilyActivitySelection.union(selections)
        overageBlockedTokens = union.applicationTokens.compactMap {
            try? PropertyListEncoder().encode($0)
        }

        if let session = try? BreakQuotaEngine(context: context).openSession() {
            overageRemaining = max(0, BreakQuotaEngine.overageHardCap - session.overageTime)
        } else {
            overageRemaining = 0
        }
        showingOverage = true
    }
}
