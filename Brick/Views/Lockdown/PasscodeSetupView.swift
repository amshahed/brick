import SwiftData
import SwiftUI

struct PasscodeSetupView: View {
    enum Purpose {
        case firstTime
        case change
    }

    let purpose: Purpose
    var onComplete: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PasscodeMode = .userChosen
    @State private var step: Step = .chooseMode
    @State private var code1 = ""
    @State private var code2 = ""
    @State private var generatedCode: String = ""
    @State private var errorText: String?

    private enum Step {
        case chooseMode
        case enterUser
        case confirmUser
        case showGenerated
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .chooseMode: chooseModeView
                case .enterUser: enterUserView
                case .confirmUser: confirmUserView
                case .showGenerated: showGeneratedView
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if purpose == .change {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(purpose == .firstTime)
        }
    }

    private var title: String {
        switch purpose {
        case .firstTime: "Set passcode"
        case .change: "Change passcode"
        }
    }

    private var chooseModeView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Lockdown passcode")
                    .font(.title3.bold())
                Text("Prevents you from disabling Brick during an active block. Pick the mode that fits your commitment style.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button {
                    mode = .userChosen
                    step = .enterUser
                } label: {
                    row(
                        title: "Pick your own passcode",
                        subtitle: "4–6 digit code you'll remember."
                    )
                }
                .buttonStyle(.plain)

                Button {
                    mode = .appGenerated
                    generatedCode = PasscodeService.generateRandom()
                    step = .showGenerated
                } label: {
                    row(
                        title: "Generate random passcode",
                        subtitle: "6-digit code — write it down somewhere inconvenient."
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 24)
    }

    private var enterUserView: some View {
        VStack(spacing: 16) {
            Text("Enter a 4–6 digit passcode")
                .font(.headline)
            SecureField("Passcode", text: $code1)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
                .onChange(of: code1) { _, new in
                    code1 = String(new.filter { $0.isNumber }.prefix(6))
                    errorText = nil
                }

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }

            Button("Next") {
                guard PasscodeService.isValidUserChosen(code1) else {
                    errorText = "Passcode must be 4–6 digits."
                    return
                }
                step = .confirmUser
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(code1.count < 4)

            Spacer()
        }
        .padding(.top, 24)
    }

    private var confirmUserView: some View {
        VStack(spacing: 16) {
            Text("Re-enter your passcode")
                .font(.headline)
            SecureField("Confirm", text: $code2)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
                .onChange(of: code2) { _, new in
                    code2 = String(new.filter { $0.isNumber }.prefix(6))
                    errorText = nil
                }

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }

            Button("Save passcode") {
                guard code1 == code2 else {
                    errorText = "Passcodes don't match."
                    return
                }
                save(code: code1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(code2.count < 4)

            Spacer()
        }
        .padding(.top, 24)
    }

    private var showGeneratedView: some View {
        VStack(spacing: 20) {
            Text("Your passcode")
                .font(.headline)
            Text(generatedCode)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .tracking(8)
                .padding()
                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
            Text("Write this down and put it somewhere inconvenient. You'll need it to disable blocks, edit active blocklists, or uninstall Brick.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }

            Button("I wrote it down") {
                save(code: generatedCode)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(.top, 24)
    }

    private func row(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private func save(code: String) {
        do {
            try AppSettingsStore(context: context).setPasscode(code, mode: mode)
            onComplete()
            dismiss()
        } catch {
            errorText = "Couldn't save passcode: \(error.localizedDescription)"
        }
    }
}
