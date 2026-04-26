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

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. Deep Work", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section("Blocklist") {
                Picker("Blocklist", selection: $blocklist) {
                    Text("Select…").tag(Blocklist?.none)
                    ForEach(blocklists) { b in
                        Text(b.name).tag(Optional(b))
                    }
                }
            }

            Section("Weekdays") {
                ForEach(WeekdayMask.orderedWeekdays, id: \.appleWeekday) { day in
                    Toggle(day.label, isOn: Binding(
                        get: { weekdayMask.contains(day.mask) },
                        set: { on in
                            if on { weekdayMask.insert(day.mask) } else { weekdayMask.remove(day.mask) }
                        }
                    ))
                }
            }

            Section("Time") {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                if startMinutes >= endMinutes {
                    Text("Wraps past midnight")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Limit to a date range", isOn: $useDateRange)
                if useDateRange {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("Until", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
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
