import SwiftData
import SwiftUI
import UIKit

struct FocusOnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var done = false
    @State private var settings: AppSettings?

    var body: some View {
        Form {
            Section("1. Create the Focus") {
                Text("Open iOS Settings, tap Focus, then create a new Focus called \"Brick\".")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section("2. Allow your people") {
                Text("Add the contacts who should always reach you — family, on-call, close friends.")
            }

            Section("3. Automate it in Shortcuts") {
                Text("In the Shortcuts app, create a Personal Automation: when Brick's Focus status changes, turn the \"Brick\" Focus on or off accordingly.")
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section("4. Emergency bypass") {
                Text("Repeated calls from the same person within 3 minutes bypass Focus automatically. iOS handles this — nothing to configure.")
            }

            Section {
                Toggle("I've set up Focus", isOn: $done)
            }
        }
        .navigationTitle("Focus integration")
        .navigationBarTitleDisplayMode(.inline)
        .task { settings = try? AppSettingsStore(context: context).loadOrCreate() }
        .onChange(of: done) { _, newValue in
            guard newValue else { return }
            try? AppSettingsStore(context: context).markFocusOnboardingComplete()
            dismiss()
        }
    }
}
