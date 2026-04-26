import SwiftData
import SwiftUI

struct SchedulesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Schedule.createdDate, order: .forward) private var schedules: [Schedule]
    @Query private var blocklists: [Blocklist]
    @State private var showingNew = false
    @State private var pendingToggleOff: Schedule?
    @State private var pendingDelete: Schedule?
    @State private var showToggleGate = false
    @State private var showDeleteGate = false

    var body: some View {
        Group {
            if blocklists.isEmpty {
                ContentUnavailableView(
                    "Create a blocklist first",
                    systemImage: "square.stack",
                    description: Text("Schedules reference a blocklist. Make one in the Blocklists tab.")
                )
            } else if schedules.isEmpty {
                ContentUnavailableView {
                    Label("No schedules yet", systemImage: "calendar")
                } description: {
                    Text("Create a schedule to block apps automatically.")
                } actions: {
                    Button("New schedule") { showingNew = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(schedules) { schedule in
                        NavigationLink(value: schedule) {
                            ScheduleRow(
                                schedule: schedule,
                                onRequestToggleOff: {
                                    pendingToggleOff = schedule
                                    showToggleGate = true
                                }
                            )
                        }
                    }
                    .onDelete(perform: requestDelete)
                }
            }
        }
        .navigationTitle("Schedules")
        .toolbar {
            if !blocklists.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: {
                        Label("New schedule", systemImage: "plus")
                    }
                }
            }
        }
        .navigationDestination(for: Schedule.self) { schedule in
            ScheduleEditorView(mode: .edit(schedule))
        }
        .sheet(isPresented: $showingNew) {
            NavigationStack {
                ScheduleEditorView(mode: .create)
            }
        }
        .passcodeGate(
            title: "Disable active schedule",
            reason: "This schedule is currently blocking apps. Enter your passcode to turn it off.",
            isPresented: $showToggleGate
        ) {
            if let schedule = pendingToggleOff {
                try? ScheduleStore(context: context).setEnabled(schedule, false)
            }
            pendingToggleOff = nil
        }
        .passcodeGate(
            title: "Delete active schedule",
            reason: "This schedule is currently blocking apps. Enter your passcode to delete it.",
            isPresented: $showDeleteGate
        ) {
            if let schedule = pendingDelete {
                try? ScheduleStore(context: context).delete(schedule)
            }
            pendingDelete = nil
        }
    }

    private func requestDelete(at offsets: IndexSet) {
        let store = ScheduleStore(context: context)
        let lockdown = LockdownManager(context: context)
        for idx in offsets {
            let schedule = schedules[idx]
            if lockdown.isLocked(.deleteSchedule(schedule)) {
                pendingDelete = schedule
                showDeleteGate = true
            } else {
                try? store.delete(schedule)
            }
        }
    }
}

private struct ScheduleRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var schedule: Schedule
    var onRequestToggleOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(schedule.name).font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { schedule.enabled },
                    set: { newValue in
                        if !newValue, LockdownManager(context: context).isLocked(.disableSchedule(schedule)) {
                            onRequestToggleOff()
                        } else {
                            try? ScheduleStore(context: context).setEnabled(schedule, newValue)
                        }
                    }
                ))
                .labelsHidden()
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let parts = [
            schedule.blocklist?.name ?? "No blocklist",
            schedule.weekdayMask.shortDescription,
            schedule.timeRangeDescription,
        ]
        return parts.joined(separator: " · ")
    }
}
