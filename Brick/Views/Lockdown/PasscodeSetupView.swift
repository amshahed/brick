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
            icon: "lock.shield",
            heroIconSize: 80
        ) {
            VStack(spacing: Theme.Space.md) {
                Button {
                    mode = .userChosen
                    step = .enterUser
                } label: {
                    row(
                        symbol: "keyboard",
                        title: "Pick your own passcode",
                        subtitle: "4–6 digit code you'll remember.",
                        friction: "Easier to bypass",
                        recommended: false
                    )
                }
                .buttonStyle(.plain)

                Button {
                    mode = .appGenerated
                    generatedCode = PasscodeService.generateRandom()
                    step = .showGenerated
                } label: {
                    row(
                        symbol: "dice",
                        title: "Generate random passcode",
                        subtitle: "6-digit code. Write it somewhere inconvenient.",
                        friction: "Harder to bypass",
                        recommended: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @State private var errorPulse: Int = 0

    private var enterUserView: some View {
        OnboardingStep(
            eyebrow: "Set passcode · 1 of 2",
            title: "Pick a 4–6 digit code.",
            body: "You'll need this to disable blocks, edit an active blocklist, or cancel an active one-shot.",
            icon: "lock",
            heroIconSize: 80,
            alignment: .center,
            titleSize: 28,
            errorText: errorText,
            primaryLabel: "Next",
            primaryAction: {
                guard PasscodeService.isValidUserChosen(code1) else {
                    errorText = "Passcode must be 4–6 digits."
                    errorPulse += 1
                    return
                }
                step = .confirmUser
            },
            primaryDisabled: code1.count < 4
        ) {
            PasscodeDotsField(value: $code1, errorTrigger: errorPulse)
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity)
                .onChange(of: code1) { _, _ in errorText = nil }
        }
    }

    private var confirmUserView: some View {
        OnboardingStep(
            eyebrow: "Set passcode · 2 of 2",
            title: "Re-enter to confirm.",
            icon: "lock.fill",
            heroIconSize: 80,
            alignment: .center,
            titleSize: 28,
            errorText: errorText,
            primaryLabel: "Save passcode",
            primaryAction: {
                guard code1 == code2 else {
                    errorText = "Passcodes don't match."
                    errorPulse += 1
                    code2 = ""
                    return
                }
                save(code: code1)
            },
            primaryDisabled: code2.count < 4
        ) {
            PasscodeDotsField(value: $code2, errorTrigger: errorPulse)
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity)
                .onChange(of: code2) { _, _ in errorText = nil }
        }
    }

    private var showGeneratedView: some View {
        OnboardingStep(
            eyebrow: "Your passcode",
            title: "Write this somewhere\ninconvenient.",
            body: "You'll need this to disable blocks, edit active blocklists, or cancel a one-shot. Brick will not show it to you again.",
            icon: "doc.text",
            heroIconSize: 80,
            alignment: .center,
            titleSize: 28,
            errorText: errorText,
            primaryLabel: "I wrote it down",
            primaryAction: { save(code: generatedCode) }
        ) {
            GeneratedCodePanel(code: generatedCode)
        }
    }

    private func row(
        symbol: String,
        title: String,
        subtitle: String,
        friction: String,
        recommended: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            IconPlate(symbol: symbol, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                if recommended {
                    Text("RECOMMENDED")
                        .font(Theme.label)
                        .tracking(0.8)
                        .foregroundStyle(Theme.accent)
                }
                Text(title)
                    .font(Theme.display(18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Text(friction.uppercased())
                    .font(Theme.label)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            Spacer(minLength: Theme.Space.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .cardSurface(padding: Theme.Space.md)
        .contentShape(Rectangle())
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

/// Reveal-animated display of a generated passcode. Digits fade and rise
/// in left-to-right with a 60ms stagger; once all digits land, the whole
/// panel does a single emphasis pulse so the user notices the code is
/// "ready to read". Respects reduce-motion.
private struct GeneratedCodePanel: View {
    let code: String

    @State private var revealed: Int = 0
    @State private var pulse: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(code.enumerated()), id: \.offset) { i, char in
                Text(String(char))
                    .font(Theme.statNumber(36, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.accentMuted)
                    )
                    .opacity(i < revealed ? 1 : 0)
                    .offset(y: i < revealed ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.md)
        .padding(.horizontal, Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .scaleEffect(pulse)
        .onAppear(perform: play)
    }

    private func play() {
        guard !reduceMotion else {
            revealed = code.count
            pulse = 1
            return
        }
        for i in 0..<code.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                withAnimation(.easeOut(duration: 0.22)) {
                    revealed = i + 1
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(code.count) * 0.06 + 0.15) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
                pulse = 1
            }
        }
    }
}
