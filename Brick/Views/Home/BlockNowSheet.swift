import SwiftData
import SwiftUI

struct BlockNowSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Blocklist.createdDate) private var blocklists: [Blocklist]

    @State private var durationMinutes: Int = 60
    @State private var blocklist: Blocklist?
    @State private var errorMessage: String?

    private static let presets: [(label: String, minutes: Int)] = [
        ("30m", 30), ("1h", 60), ("2h", 120), ("3h", 180), ("4h", 240),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    Picker("Preset", selection: $durationMinutes) {
                        ForEach(Self.presets, id: \.minutes) { preset in
                            Text(preset.label).tag(preset.minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $durationMinutes, in: 5...720, step: 5) {
                        Text("Custom: \(formatMinutes(durationMinutes))")
                    }
                }

                Section("Blocklist") {
                    Picker("Blocklist", selection: $blocklist) {
                        Text("Select…").tag(Blocklist?.none)
                        ForEach(blocklists) { b in
                            Text(b.name).tag(Optional(b))
                        }
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
            .navigationTitle("Block Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: start)
                        .disabled(blocklist == nil)
                }
            }
        }
    }

    private func start() {
        guard let blocklist else { return }
        let store = OneShotBlockStore(context: context)
        do {
            try store.start(blocklist: blocklist, duration: TimeInterval(durationMinutes * 60))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatMinutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let hours = m / 60
        let mins = m % 60
        return mins == 0 ? "\(hours) h" : "\(hours) h \(mins) m"
    }
}
