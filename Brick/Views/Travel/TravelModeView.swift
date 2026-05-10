import SwiftData
import SwiftUI

struct TravelModeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TravelPeriod.createdAt, order: .reverse) private var periods: [TravelPeriod]
    @State private var now: Date = .now
    @State private var startDate: Date = .now
    @State private var endDate: Date = .now.addingTimeInterval(3 * 24 * 3600)
    @State private var errorText: String?
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            if let active = activePeriod {
                activeSection(period: active)
            } else {
                inactiveSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Travel mode")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { now = $0 }
    }

    private var activePeriod: TravelPeriod? {
        periods.first { $0.isActive(at: now) }
    }

    @ViewBuilder
    private func activeSection(period: TravelPeriod) -> some View {
        Section("Status") {
            LabeledContent("Mode") {
                Text(period.isDated ? "Dated" : "Toggle")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Started") {
                Text(period.startDate.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            if let endDate = period.endDate {
                LabeledContent("Ends") {
                    Text(endDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No end date — resume manually.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Text("Schedules are suspended. One-shot blocks still work normally.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Button("End travel mode", role: .destructive) {
                try? TravelPeriodStore(context: context).end(period)
            }
        }
    }

    @ViewBuilder
    private var inactiveSection: some View {
        Section("Plan a trip") {
            DatePicker("From", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
            DatePicker("Until", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
            Button("Start dated travel") {
                do {
                    try TravelPeriodStore(context: context).startDated(from: startDate, to: endDate)
                    errorText = nil
                } catch {
                    errorText = error.localizedDescription
                }
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }

        Section("Right now") {
            Button("I'm traveling now") {
                try? TravelPeriodStore(context: context).startToggle()
            }
        }

        Section {
            Text("While traveling, schedules are suspended. You can still block apps manually via Block Now. Dated travel auto-resumes when the end date passes; toggle travel nudges you daily until you disable it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
