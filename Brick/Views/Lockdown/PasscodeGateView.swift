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
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.accentMuted)
                            .frame(width: 56, height: 56)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        SectionEyebrow(text: "Locked")
                        Text(title)
                            .font(Theme.display(28, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, Theme.Space.xs)
                    }
                }

                SecureField("Passcode", text: $code)
                    .textContentType(.password)
                    .keyboardType(.numberPad)
                    .font(Theme.statNumber(28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, Theme.Space.lg)
                    .padding(.horizontal, Theme.Space.xl)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .disabled(isLockedOut)
                    .accessibilityIdentifier("passcode.gate.field")
                    .onChange(of: code) { old, new in
                        let sanitized = String(new.filter { $0.isNumber }.prefix(6))
                        if sanitized != new { code = sanitized }
                        if sanitized.count > old.count {
                            errorText = nil
                        }
                    }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("passcode.gate.error")
                }

                if isLockedOut {
                    Text("Too many attempts. Try again in \(cooldownSeconds)s.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Unlock", action: submit)
                    .buttonStyle(.brickPrimary)
                    .opacity(code.count < 4 || isLockedOut ? 0.4 : 1)
                    .disabled(code.count < 4 || isLockedOut)
                    .accessibilityIdentifier("passcode.gate.unlock")
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas.ignoresSafeArea())
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
