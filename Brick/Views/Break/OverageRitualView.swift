import FamilyControls
import ManagedSettings
import SwiftUI

/// Friction gate users must pass through to start a break after their
/// 10-min quota is exhausted but before the 15-min overage hard cap kicks in.
/// Requires (a) ≥80 chars of free-form justification and (b) a 20-second
/// wait. Only then is "Confirm override" tappable.
struct OverageRitualView: View {
    let preselectedTokenData: Data?
    let blockedTokens: [Data]
    let remainingOverage: TimeInterval
    let onConfirm: (ApplicationToken, TimeInterval) -> Void
    let onCancel: () -> Void

    @State private var selectedTokenData: Data?
    @State private var justification: String = ""
    @State private var secondsRemaining: Int = 20
    @State private var durationMinutes: Int = 1

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let minChars = 80
    private static let waitSeconds = 20
    private static let presetMinutes: [Int] = [1, 2, 3, 5]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Override the limit", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Your block will be extended by 2× whatever time you take here. Up to \(Int(remainingOverage / 60)) min left before you're locked out for the rest of this block.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if preselectedTokenData == nil {
                Section("Pick one app") {
                    ForEach(blockedTokens, id: \.self) { tokenData in
                        Button {
                            selectedTokenData = tokenData
                        } label: {
                            HStack {
                                tokenLabel(for: tokenData)
                                Spacer()
                                if selectedTokenData == tokenData {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            Section("Duration") {
                Picker("Minutes", selection: $durationMinutes) {
                    ForEach(durationOptions, id: \.self) { m in
                        Text("\(m) min").tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextEditor(text: $justification)
                    .frame(minHeight: 120)
                HStack {
                    Text("\(justification.count) / \(Self.minChars)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(charCountSatisfied ? Color.primary : Color.secondary)
                    Spacer()
                    if charCountSatisfied {
                        Label("ok", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Why are you overriding?")
            } footer: {
                Text("Free-form, at least \(Self.minChars) characters. Not stored or sent anywhere — it's just a speed bump.")
            }

            Section {
                HStack {
                    if secondsRemaining > 0 {
                        Label("Wait \(secondsRemaining)s", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("Override")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm override") { confirmIfPossible() }
                    .disabled(!canConfirm)
            }
        }
        .onAppear {
            secondsRemaining = Self.waitSeconds
            if let preselectedTokenData, blockedTokens.contains(preselectedTokenData) {
                selectedTokenData = preselectedTokenData
            }
            if durationMinutes > maxMinutes {
                durationMinutes = max(1, maxMinutes)
            }
        }
        .onReceive(ticker) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
        }
    }

    // MARK: - Derived

    private var maxMinutes: Int {
        max(1, Int(remainingOverage / 60))
    }

    private var durationOptions: [Int] {
        Self.presetMinutes.filter { $0 <= maxMinutes }
    }

    private var charCountSatisfied: Bool {
        justification.count >= Self.minChars
    }

    private var resolvedTokenData: Data? {
        preselectedTokenData ?? selectedTokenData
    }

    private var canConfirm: Bool {
        charCountSatisfied
            && secondsRemaining == 0
            && resolvedTokenData != nil
            && durationMinutes > 0
            && remainingOverage >= 60
    }

    // MARK: - Actions

    private func confirmIfPossible() {
        guard let tokenData = resolvedTokenData,
              let token = try? PropertyListDecoder()
                .decode(ApplicationToken.self, from: tokenData) else { return }
        onConfirm(token, TimeInterval(durationMinutes * 60))
    }

    @ViewBuilder
    private func tokenLabel(for data: Data) -> some View {
        if let token = try? PropertyListDecoder()
            .decode(ApplicationToken.self, from: data) {
            Label(token)
                .lineLimit(1)
        } else {
            Text("Unknown app")
        }
    }
}
