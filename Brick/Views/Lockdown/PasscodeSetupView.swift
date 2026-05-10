import SwiftData
import SwiftUI

struct PasscodeSetupView: View {
    enum Purpose {
        case firstTime
        case change
    }

    let purpose: Purpose
    /// When true (default), wraps content in its own NavigationStack — used
    /// when this view is presented as a modal sheet. Set to false when
    /// embedded inside another NavigationStack (e.g., OnboardingView), so
    /// the parent's toolbar/navbar is preserved.
    var embedInNavigationStack: Bool = true
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
        Group {
            if embedInNavigationStack {
                NavigationStack { content }
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch step {
            case .chooseMode: chooseModeView
            case .enterUser: enterUserView
            case .confirmUser: confirmUserView
            case .showGenerated: showGeneratedView
            }
        }
        .navigationTitle(embedInNavigationStack ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedInNavigationStack && purpose == .change {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(purpose == .firstTime)
    }

    private var title: String {
        switch purpose {
        case .firstTime: "Set passcode"
        case .change: "Change passcode"
        }
    }

    private var chooseModeView: some View {
        OnboardingStep(
            eyebrow: "Lockdown passcode",
            title: "Pick a\ncommitment mode.",
            body: "The passcode gates disabling blocks, editing the active blocklist, and cancelling a one-shot. Pick how hard it should be to bypass.",
            icon: "lock.shield"
        ) {
            VStack(spacing: Theme.Space.sm) {
                Button {
                    mode = .userChosen
                    step = .enterUser
                } label: {
                    row(
                        title: "Pick your own passcode",
                        subtitle: "4–6 digit code you'll remember.",
                        emphasis: false
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
                        subtitle: "6-digit code. Write it somewhere inconvenient. Higher friction.",
                        emphasis: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var enterUserView: some View {
        OnboardingStep(
            eyebrow: "Set passcode · 1 of 2",
            title: "Pick a 4–6 digit code.",
            body: "You'll need this to disable blocks, edit an active blocklist, or cancel an active one-shot.",
            errorText: errorText,
            primaryLabel: "Next",
            primaryAction: {
                guard PasscodeService.isValidUserChosen(code1) else {
                    errorText = "Passcode must be 4–6 digits."
                    return
                }
                step = .confirmUser
            },
            primaryDisabled: code1.count < 4
        ) {
            passcodeField($code1, placeholder: "Passcode")
        }
    }

    private var confirmUserView: some View {
        OnboardingStep(
            eyebrow: "Set passcode · 2 of 2",
            title: "Re-enter to confirm.",
            errorText: errorText,
            primaryLabel: "Save passcode",
            primaryAction: {
                guard code1 == code2 else {
                    errorText = "Passcodes don't match."
                    return
                }
                save(code: code1)
            },
            primaryDisabled: code2.count < 4
        ) {
            passcodeField($code2, placeholder: "Confirm")
        }
    }

    private func passcodeField(_ binding: Binding<String>, placeholder: String) -> some View {
        SecureField(placeholder, text: binding)
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
            .onChange(of: binding.wrappedValue) { old, new in
                let sanitized = String(new.filter { $0.isNumber }.prefix(6))
                if sanitized != new { binding.wrappedValue = sanitized }
                if sanitized.count > old.count { errorText = nil }
            }
    }

    private var showGeneratedView: some View {
        OnboardingStep(
            eyebrow: "Your passcode",
            title: "Write this somewhere\ninconvenient.",
            body: "You'll need this to disable blocks, edit active blocklists, or cancel a one-shot. Brick will not show it to you again.",
            errorText: errorText,
            primaryLabel: "I wrote it down",
            primaryAction: { save(code: generatedCode) }
        ) {
            VStack(spacing: Theme.Space.md) {
                Text(generatedCode)
                    .font(Theme.statNumber(40, weight: .semibold))
                    .tracking(8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.lg)
                    .padding(.horizontal, Theme.Space.xl)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.accentMuted)
                    )
            }
        }
    }

    private func row(title: String, subtitle: String, emphasis: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(emphasis ? Theme.accentMuted : Color.primary.opacity(0.05))
                    .frame(width: 40, height: 40)
                Image(systemName: emphasis ? "dice" : "keyboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(emphasis ? Theme.accent : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.display(16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .cardSurface(padding: Theme.Space.md)
    }

    private func save(code: String) {
        do {
            try AppSettingsStore(context: context).setPasscode(code, mode: mode)
            // Caller's onComplete decides whether to dismiss this view (via
            // its sheet binding) or advance an embedded onboarding state.
            // Don't call `dismiss()` here — when this view is embedded in
            // OnboardingView (a fullScreenCover), `dismiss()` bubbles up to
            // the cover and tears down the entire onboarding flow.
            onComplete()
        } catch {
            errorText = "Couldn't save passcode: \(error.localizedDescription)"
        }
    }
}
