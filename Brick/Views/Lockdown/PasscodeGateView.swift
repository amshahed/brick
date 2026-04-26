import SwiftUI

struct PasscodeGateView: View {
    let title: String
    let reason: String
    let settings: AppSettings
    var onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code: String = ""
    @State private var attempts: Int = 0
    @State private var cooldownUntil: Date?
    @State private var now: Date = .now
    @State private var errorText: String?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 24)

                SecureField("Passcode", text: $code)
                    .textContentType(.password)
                    .keyboardType(.numberPad)
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
                    .padding(.horizontal)
                    .disabled(isLockedOut)
                    .onChange(of: code) { _, new in
                        code = String(new.filter { $0.isNumber }.prefix(6))
                        errorText = nil
                    }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if isLockedOut {
                    Text("Too many attempts. Try again in \(cooldownSeconds)s.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Unlock", action: submit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(code.count < 4 || isLockedOut)

                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onReceive(tick) { instant in
                now = instant
                if let until = cooldownUntil, instant >= until {
                    cooldownUntil = nil
                }
            }
        }
    }

    private var isLockedOut: Bool {
        if let until = cooldownUntil, now < until { return true }
        return false
    }

    private var cooldownSeconds: Int {
        guard let until = cooldownUntil else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    private func submit() {
        guard let hash = settings.passcodeHash, let salt = settings.passcodeSalt else {
            errorText = "No passcode configured."
            return
        }
        if PasscodeService.verify(code, hash: hash, salt: salt) {
            onUnlocked()
            dismiss()
            return
        }
        attempts += 1
        code = ""
        if attempts >= 3 {
            cooldownUntil = Date.now.addingTimeInterval(30)
            attempts = 0
            errorText = nil
        } else {
            errorText = "Incorrect. \(3 - attempts) attempt\(attempts == 2 ? "" : "s") left."
        }
    }
}
