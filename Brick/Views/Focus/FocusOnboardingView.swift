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
            Section {
                Text("iOS doesn't let third-party apps activate Focus modes. Brick teaches you how to wire iOS to do it for you — once set up, your Brick Focus turns on alongside your blocks and lets your allowed contacts ring through.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("1. Create the Focus") {
                Text("Open iOS Settings → Focus → tap \"+\" → name it \"Brick\". Add the people who should always reach you (family, on-call, partner) under Allowed People.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section("2. Choose how Focus turns on") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recurring blocks (recommended)")
                        .font(.subheadline.bold())
                    Text("Inside your Brick Focus → Add Schedule → mirror the days/times of your Brick schedule. iOS turns Focus on and off automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("One-shot blocks")
                        .font(.subheadline.bold())
                    Text("In Shortcuts → Automation → \"+\" → choose \"App\" → select Brick → Is Opened → next, action \"Set Focus\" → Brick → Turn On. Now Focus turns on whenever you open Brick.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section("3. Emergency bypass") {
                Text("Repeated calls from the same person within 3 minutes bypass Focus automatically. iOS handles this — nothing to configure.")
            }

            Section {
                Toggle("I've set up Focus", isOn: $done)
            } footer: {
                Text("This is a self-report. Brick can't verify your iOS Focus setup — flipping this just hides the home-screen nudge.")
                    .font(.caption2)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
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
