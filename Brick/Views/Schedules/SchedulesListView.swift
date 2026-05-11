import SwiftData
import SwiftUI

struct SchedulesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Schedule.createdDate, order: .forward) private var schedules: [Schedule]
    @Query private var blocklists: [Blocklist]
    @State private var showingNew = false
    @State private var showingTemplatePicker = false
    @State private var pendingToggleOff: Schedule?
    @State private var pendingDelete: Schedule?
    @State private var showToggleGate = false
    @State private var showDeleteGate = false

    var body: some View {
        Group {
            if blocklists.isEmpty {
                BrickEmptyState(
                    eyebrow: "Schedules",
                    title: "Block on a\nrecurring rhythm.",
                    body: "Pick a template to set up your first recurring block in one tap. You can edit it later — name, apps, and times are all yours.",
                    primaryActionLabel: "Start from template",
                    primaryAction: { showingTemplatePicker = true }
                )
            } else if schedules.isEmpty {
                BrickEmptyState(
                    eyebrow: "Schedules",
                    title: "No schedules yet.",
                    body: "Create a schedule to block apps automatically on a recurring rhythm — or start from a template.",
                    primaryActionLabel: "New schedule",
                    primaryAction: { showingNew = true },
                    secondaryActionLabel: "Start from template",
                    secondaryAction: { showingTemplatePicker = true }
                )
            } else {
                List {
                    ForEach(schedules) { schedule in
                        ZStack {
                            NavigationLink(value: schedule) { EmptyView() }
                                .opacity(0)
                            ScheduleRow(
                                schedule: schedule,
                                onRequestToggleOff: {
                                    pendingToggleOff = schedule
                                    showToggleGate = true
                                }
                            )
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: Theme.Space.lg, bottom: 6, trailing: Theme.Space.lg))
                        // Explicit swipeActions instead of `.onDelete` —
                        // the embedded NavigationLink in the row's ZStack
                        // confused iOS's implicit delete handler, leading
                        // to apparent hangs. (#22)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                requestDelete(schedule: schedule)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !blocklists.isEmpty {
                        Button { showingNew = true } label: {
                            Label("New schedule", systemImage: "plus")
                        }
                    }
                    Button { showingTemplatePicker = true } label: {
                        Label("Start from template", systemImage: "sparkles")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
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
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerSheet()
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

    private func requestDelete(schedule: Schedule) {
        let store = ScheduleStore(context: context)
        let lockdown = LockdownManager(context: context)
        if lockdown.isLocked(.deleteSchedule(schedule)) {
            pendingDelete = schedule
            showDeleteGate = true
        } else {
            try? store.delete(schedule)
        }
    }
}

/// Row uses plain props captured at construction time instead of an
/// `@Bindable` reference to the SwiftData model. Reason: when the parent
/// deletes a schedule via swipe, SwiftUI keeps the deleted row in the
/// view tree for the slide-out animation. An `@Bindable` Toggle binding
/// would fire one more `.get` on the invalidated model during that frame
/// and trap with `SwiftData/BackingData.swift:1039: Fatal error: This
/// model instance was invalidated...`. (#23) Plain props make the row
/// stateless and safe to render even after the underlying row is gone.
private struct ScheduleRow: View {
    @Environment(\.modelContext) private var context

    let schedule: Schedule
    let name: String
    let enabled: Bool
    let timeLine: String
    let metaLine: String
    let onRequestToggleOff: () -> Void

    init(schedule: Schedule, onRequestToggleOff: @escaping () -> Void) {
        self.schedule = schedule
        self.name = schedule.name
        self.enabled = schedule.enabled
        self.timeLine = "\(schedule.weekdayMask.shortDescription) · \(schedule.timeRangeDescription)"
        self.metaLine = schedule.blocklist?.name ?? "No blocklist"
        self.onRequestToggleOff = onRequestToggleOff
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(enabled ? Theme.accentMuted : Color.primary.opacity(0.05))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? Theme.accent : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.display(17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(timeLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(metaLine)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.sm)

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    // Toggle action re-resolves the schedule each tap via
                    // its id, so we never touch a stale snapshot.
                    let id = schedule.persistentModelID
                    let store = ScheduleStore(context: context)
                    guard let fresh = try? context.fetch(
                        FetchDescriptor<Schedule>(predicate: #Predicate { $0.persistentModelID == id })
                    ).first else { return }
                    if !newValue, LockdownManager(context: context).isLocked(.disableSchedule(fresh)) {
                        onRequestToggleOff()
                    } else {
                        try? store.setEnabled(fresh, newValue)
                    }
                }
            ))
            .labelsHidden()
            .tint(Theme.accent)
        }
        .cardSurface(padding: Theme.Space.md)
        .contentShape(Rectangle())
    }
}
