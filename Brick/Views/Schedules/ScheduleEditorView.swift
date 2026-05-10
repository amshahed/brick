import SwiftData
import SwiftUI

struct ScheduleEditorView: View {
    enum Mode {
        case create
        case edit(Schedule)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Blocklist.createdDate) private var blocklists: [Blocklist]

    let mode: Mode

    @State private var name = ""
    @State private var blocklist: Blocklist?
    @State private var weekdayMask: WeekdayMask = .weekdays
    @State private var startTime = Self.defaultStart
    @State private var endTime = Self.defaultEnd
    @State private var useDateRange = false
    @State private var startDate: Date = .now
    @State private var endDate: Date = .now.addingTimeInterval(7 * 24 * 3600)
    @State private var errorMessage: String?
    @State private var isFieldsLocked = false
    @State private var isUnlocked = false
    @State private var showUnlockGate = false

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. Deep Work", text: $name)
                    .textInputAutocapitalization(.words)
            }

            if isFieldsBlockedByGate {
                Section {
                    Text("This schedule is currently active. Time, weekday, and blocklist edits are locked. Tap Unlock to enter your passcode, or rename it (always allowed).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Unlock to edit") { showUnlockGate = true }
                        .buttonStyle(.brickSecondary)
                        .padding(.vertical, 4)
                }
            }

            Section("Blocklist") {
                Picker("Blocklist", selection: $blocklist) {
                    Text("Select…").tag(Blocklist?.none)
                    ForEach(blocklists) { b in
                        Text(b.name).tag(Optional(b))
                    }
                }
                .disabled(isFieldsBlockedByGate)
            }

            Section("Weekdays") {
                ForEach(WeekdayMask.orderedWeekdays, id: \.appleWeekday) { day in
                    Toggle(day.label, isOn: Binding(
                        get: { weekdayMask.contains(day.mask) },
                        set: { on in
                            if on { weekdayMask.insert(day.mask) } else { weekdayMask.remove(day.mask) }
                        }
                    ))
                    .disabled(isFieldsBlockedByGate)
                }
            }

            Section("Time") {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    .disabled(isFieldsBlockedByGate)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    .disabled(isFieldsBlockedByGate)
                if startMinutes >= endMinutes {
                    Text("Wraps past midnight")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Limit to a date range", isOn: $useDateRange)
                    .disabled(isFieldsBlockedByGate)
                if useDateRange {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                        .disabled(isFieldsBlockedByGate)
                    DatePicker("Until", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .disabled(isFieldsBlockedByGate)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .onAppear(perform: load)
        .passcodeGate(
            title: "Edit active schedule",
            reason: "This schedule is currently running. Enter your passcode to change its time, weekdays, dates, or blocklist.",
            isPresented: $showUnlockGate
        ) {
            isUnlocked = true
        }
    }

    /// True when this is an edit of a currently-active schedule and the
    /// user hasn't unlocked. Renaming stays allowed; everything else gets
    /// disabled with a banner explaining why.
    private var isFieldsBlockedByGate: Bool {
        isFieldsLocked && !isUnlocked
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && blocklist != nil
            && !weekdayMask.isEmpty
            && startMinutes != endMinutes
    }

    private var startMinutes: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return ScheduleClock.minutes(from: comps.hour ?? 0, minute: comps.minute ?? 0)
    }

    private var endMinutes: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        return ScheduleClock.minutes(from: comps.hour ?? 0, minute: comps.minute ?? 0)
    }

    private func load() {
        guard case .edit(let schedule) = mode else { return }
        name = schedule.name
        blocklist = schedule.blocklist
        weekdayMask = schedule.weekdayMask
        startTime = dateFor(minutes: schedule.startMinute)
        endTime = dateFor(minutes: schedule.endMinute)
        if let s = schedule.startDate, let e = schedule.endDate {
            useDateRange = true
            startDate = s
            endDate = e
        }
        isFieldsLocked = LockdownManager(context: context)
            .isLocked(.editScheduleFields(schedule))
    }

    private func save() {
        guard let blocklist else { return }
        let store = ScheduleStore(context: context)
        do {
            switch mode {
            case .create:
                try store.create(
                    name: name,
                    blocklist: blocklist,
                    weekdayMask: weekdayMask,
                    startMinute: startMinutes,
                    endMinute: endMinutes,
                    startDate: useDateRange ? startDate : nil,
                    endDate: useDateRange ? endDate : nil
                )
            case .edit(let schedule):
                try store.update(
                    schedule,
                    name: name,
                    blocklist: blocklist,
                    weekdayMask: weekdayMask,
                    startMinute: startMinutes,
                    endMinute: endMinutes,
                    startDate: useDateRange ? startDate : nil,
                    endDate: useDateRange ? endDate : nil
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dateFor(minutes: Int) -> Date {
        let (h, m) = ScheduleClock.components(from: minutes)
        return Calendar.current.date(
            bySettingHour: h, minute: m, second: 0, of: .now
        ) ?? .now
    }

    private static var defaultStart: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    }

    private static var defaultEnd: Date {
        Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now
    }
}

private extension ScheduleEditorView.Mode {
    var title: String {
        switch self {
        case .create: "New Schedule"
        case .edit: "Edit Schedule"
        }
    }
}
