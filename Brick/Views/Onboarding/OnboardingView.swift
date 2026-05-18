import FamilyControls
import SwiftData
import SwiftUI
import UIKit

/// First-launch flow: welcome → FC auth → Brick passcode → Screen Time
/// passcode → templates → apps → done. Presented as a `fullScreenCover`
/// from `RootView`. Sets `AppSettings.hasCompletedOnboarding = true` on
/// the final step.
///
/// Navigation: every step (except welcome) shows a Back button in the
/// toolbar. Forward transitions go through `go(to:)` which records history.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .welcome
    @State private var history: [Step] = []
    @State private var direction: NavDirection = .forward
    @State private var authRequested = false
    @State private var authError: String?
    @State private var screenTimeSlide: Int = 0
    @State private var selectedTemplates: Set<String> = []
    @State private var dateRanges: [String: DateRange] = [:]
    @State private var appsQueueEntries: [QueueEntry] = []
    @State private var pickerIndex: Int = 0
    @State private var pickerSelection: FamilyActivitySelection = .init()
    @State private var showingPicker = false
    @State private var errorText: String?
    @State private var finishError: String?
    @State private var finishAttempts: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Int {
        case welcome, auth, passcode, screenTimePasscode, templates, apps, done
    }

    enum NavDirection { case forward, backward }

    struct DateRange: Equatable {
        var start: Date
        var end: Date
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .auth: authStep
                    case .passcode: passcodeStep
                    case .screenTimePasscode: screenTimePasscodeStep
                    case .templates: templateStep
                    case .apps: appsStep
                    case .done: doneStep
                    }
                }
                .id(step)
                .transition(slideTransition)
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86), value: step)
            .padding()
            .interactiveDismissDisabled()
            .toolbar { toolbarContent }
        }
        .task {
            // If iOS already has the Screen Time grant from a prior run,
            // skip the auth step — the system won't show the dialog again
            // anyway, so showing this screen is just confusing friction.
            if AuthorizationCenter.shared.authorizationStatus == .approved {
                authRequested = true
                authError = nil
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !history.isEmpty {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        ToolbarItem(placement: .principal) {
            Text(stepTitle).font(.headline)
        }
    }

    private var stepTitle: String {
        switch step {
        case .welcome: ""
        case .auth: "Permission"
        case .passcode: "Passcode"
        case .screenTimePasscode: "Lock down"
        case .templates: "Templates"
        case .apps: "Apps"
        case .done: ""
        }
    }

    // MARK: - Step transitions (with history tracking)

    private func go(to next: Step) {
        direction = .forward
        history.append(step)
        step = next
    }

    private func goBack() {
        direction = .backward
        guard let previous = history.popLast() else { return }
        step = previous
    }

    /// Direction-aware slide. Forward moves the new step in from the
    /// trailing edge; backward mirrors it. Reduce-motion users get a flat
    /// crossfade.
    private var slideTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        let inEdge: Edge = direction == .forward ? .trailing : .leading
        let outEdge: Edge = direction == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: inEdge).combined(with: .opacity),
            removal: .move(edge: outEdge).combined(with: .opacity)
        )
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        OnboardingStep(
            eyebrow: "Welcome",
            title: "Block apps\nwith real commitment.",
            body: "Brick is a focus tool that adds friction where other blockers fold. A passcode prevents impulse breaks. A structured budget keeps overage honest.",
            customHero: AnyView(BrickHeroLogo(size: 144)),
            alignment: .center,
            titleSize: 34,
            primaryLabel: "Get started",
            primaryAction: {
                if AuthorizationCenter.shared.authorizationStatus == .approved {
                    go(to: .passcode)
                } else {
                    go(to: .auth)
                }
            }
        )
    }

    private var authStep: some View {
        OnboardingStep(
            eyebrow: "Permission",
            title: "Screen Time access.",
            body: "Brick uses Apple's Screen Time framework to shield apps. Tap Grant permission and then Continue on the system dialog.",
            icon: "lock.shield",
            heroIconSize: 96,
            alignment: .center,
            titleSize: 32,
            errorText: authError,
            primaryLabel: authPrimaryTitle,
            primaryAction: {
                if authSucceeded {
                    go(to: .passcode)
                } else {
                    Task { await requestAuth() }
                }
            }
        )
    }

    private var authSucceeded: Bool {
        authRequested && authError == nil
    }

    private var authPrimaryTitle: String {
        if authSucceeded { return "Continue" }
        if authRequested { return "Try again" }
        return "Grant permission"
    }

    private var passcodeStep: some View {
        // Embed PasscodeSetupView without its own NavigationStack so the
        // parent toolbar (with Back) remains visible. On save complete,
        // advance to the next step.
        PasscodeSetupView(
            purpose: .firstTime,
            embedInNavigationStack: false
        ) {
            go(to: .screenTimePasscode)
        }
    }

    // MARK: - Screen Time slideshow

    private var screenTimePasscodeStep: some View {
        VStack(spacing: 0) {
            slideshowProgress
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)

            TabView(selection: $screenTimeSlide) {
                stpIntroSlide.tag(0)
                stpPasscodeSlide.tag(1)
                stpDeletionSlide.tag(2)
                stpConfirmSlide.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Re-key on the slide index so each slide is a fresh view —
            // the icon entrance animation in `OnboardingStep` re-fires
            // when the user swipes.
            .id(screenTimeSlide)

            Button("Skip for now") { go(to: .templates) }
                .buttonStyle(.brickSecondary)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    private var slideshowProgress: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i == screenTimeSlide ? Theme.accent : Color.primary.opacity(0.08))
                    .frame(width: i == screenTimeSlide ? 22 : 8, height: 6)
                    .animation(.spring(response: 0.32, dampingFraction: 0.85), value: screenTimeSlide)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var stpIntroSlide: some View {
        OnboardingStep(
            eyebrow: "1 of 4",
            title: "Two iOS steps\nblock uninstall.",
            body: "Brick alone can't stop you from deleting it during a block. iOS has the lock — these next slides walk you through enabling it.",
            icon: "lock.iphone",
            heroIconSize: 96,
            alignment: .center,
            titleSize: 30
        ) { EmptyView() }
    }

    private var stpPasscodeSlide: some View {
        OnboardingStep(
            eyebrow: "2 of 4",
            title: "Set a Screen Time\npasscode.",
            body: "In Settings → Screen Time → Lock Screen Time Settings. Pick a passcode you don't easily reach for.",
            icon: "key.fill",
            heroIconSize: 96,
            alignment: .center,
            titleSize: 30,
            primaryLabel: "Open Settings",
            primaryAction: openSettings
        ) { EmptyView() }
    }

    private var stpDeletionSlide: some View {
        OnboardingStep(
            eyebrow: "3 of 4",
            title: "Disallow\napp deletion.",
            body: "Settings → Screen Time → Content & Privacy Restrictions → On → iTunes & App Store Purchases → Deleting Apps → Don't Allow. This is iOS-wide, not just Brick — it's the only way iOS lets a third-party app be uninstall-protected.",
            icon: "trash.slash.fill",
            heroIconSize: 96,
            alignment: .center,
            titleSize: 30,
            primaryLabel: "Open Settings",
            primaryAction: openSettings
        ) { EmptyView() }
    }

    private var stpConfirmSlide: some View {
        OnboardingStep(
            eyebrow: "4 of 4",
            title: "All set?",
            body: "Once you've done both steps in Settings, continue. You can revisit this later from Settings if you want to verify.",
            icon: "checkmark.shield.fill",
            heroIconSize: 96,
            alignment: .center,
            titleSize: 32,
            primaryLabel: "I've finished both steps",
            primaryAction: { go(to: .templates) }
        ) { EmptyView() }
    }

    /// iOS provides no public URL to open Settings root or a specific
    /// section from a third-party app — `App-prefs:` and similar were
    /// blocked starting in iOS 16. `openSettingsURLString` opens the
    /// Settings app to Brick's own page; the user backs out from there.
    /// We acknowledge this in copy rather than pretending otherwise.
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Templates / apps / done

    private var templateStep: some View {
        OnboardingStep(
            eyebrow: "Templates",
            title: "Starter rhythms.",
            body: "Pick any that match how you'd like Brick to fire automatically. You can skip this and build schedules from scratch later.",
            errorText: errorText,
            primaryLabel: selectedTemplates.isEmpty ? "Continue" : "Pick apps",
            primaryAction: applyTemplatesAndAdvance,
            secondaryLabel: "Skip",
            secondaryAction: finish
        ) {
            VStack(spacing: Theme.Space.sm) {
                ForEach(TemplateLibrary.all) { template in
                    templateRow(template)
                }
            }
        }
    }

    @ViewBuilder
    private var appsStep: some View {
        if appsQueueEntries.isEmpty {
            doneStep
        } else if pickerIndex >= appsQueueEntries.count {
            doneStep
                .onAppear { finish() }
        } else {
            let current = appsQueueEntries[pickerIndex]
            OnboardingStep(
                eyebrow: "Apps · \(pickerIndex + 1) of \(appsQueueEntries.count)",
                title: "Pick apps for\n\(current.blocklist.name).",
                body: current.template.description + " You can edit any of this from Blocklists later.",
                icon: "square.stack",
                errorText: errorText,
                primaryLabel: "Open app picker",
                primaryAction: {
                    pickerSelection = current.blocklist.selection
                    showingPicker = true
                },
                secondaryLabel: "Skip for now",
                secondaryAction: { advancePicker() }
            ) { EmptyView() }
            .familyActivityPicker(isPresented: $showingPicker, selection: $pickerSelection)
            .onChange(of: showingPicker) { _, presenting in
                if !presenting {
                    do {
                        try BlocklistStore(context: context)
                            .updateSelection(current.blocklist, to: pickerSelection)
                        errorText = nil
                        advancePicker()
                    } catch {
                        errorText = "Couldn't save your apps: \(error.localizedDescription). Tap Skip for now to continue and try editing later from Blocklists."
                    }
                }
            }
        }
    }

    private var doneStep: some View {
        OnboardingStep(
            eyebrow: "Done",
            title: "You're ready.",
            body: "Brick is active. Start a one-off block now from the Home tab or let your schedules kick in.",
            icon: "checkmark.seal.fill",
            heroIconSize: 96,
            alignment: .center,
            titleSize: 36,
            errorText: finishError,
            primaryLabel: finishError == nil ? "Open Brick" : "Continue anyway",
            primaryAction: { finish() }
        ) { EmptyView() }
    }

    // MARK: - Template row

    @ViewBuilder
    private func templateRow(_ template: Template) -> some View {
        let isSelected = selectedTemplates.contains(template.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(Theme.display(16, weight: .semibold))
                    Text(template.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : .secondary.opacity(0.7))
            }
            if isSelected && template.requiresDateRange {
                let binding = rangeBinding(for: template)
                DatePicker(
                    "Starts",
                    selection: binding.start,
                    displayedComponents: .date
                )
                .font(.footnote)
                DatePicker(
                    "Ends",
                    selection: binding.end,
                    in: binding.start.wrappedValue...,
                    displayedComponents: .date
                )
                .font(.footnote)
            }
        }
        .cardSurface(padding: Theme.Space.md)
        .contentShape(Rectangle())
        .onTapGesture { toggle(template) }
    }

    private func toggle(_ template: Template) {
        if selectedTemplates.contains(template.id) {
            selectedTemplates.remove(template.id)
            dateRanges.removeValue(forKey: template.id)
        } else {
            selectedTemplates.insert(template.id)
            if template.requiresDateRange {
                dateRanges[template.id] = DateRange(
                    start: .now,
                    end: .now.addingTimeInterval(7 * 24 * 3600)
                )
            }
        }
    }

    private func rangeBinding(for template: Template) -> (start: Binding<Date>, end: Binding<Date>) {
        let key = template.id
        let start = Binding<Date>(
            get: { dateRanges[key]?.start ?? .now },
            set: { dateRanges[key] = DateRange(start: $0, end: dateRanges[key]?.end ?? $0.addingTimeInterval(7 * 24 * 3600)) }
        )
        let end = Binding<Date>(
            get: { dateRanges[key]?.end ?? .now.addingTimeInterval(7 * 24 * 3600) },
            set: { dateRanges[key] = DateRange(start: dateRanges[key]?.start ?? .now, end: $0) }
        )
        return (start, end)
    }

    // MARK: - Apply templates

    struct QueueEntry: Equatable {
        let template: Template
        let blocklist: Blocklist
        static func == (lhs: QueueEntry, rhs: QueueEntry) -> Bool {
            lhs.template.id == rhs.template.id && lhs.blocklist.name == rhs.blocklist.name
        }
    }

    private func applyTemplatesAndAdvance() {
        errorText = nil
        if selectedTemplates.isEmpty {
            finish()
            return
        }
        let applier = TemplateApplier(context: context)
        var entries: [QueueEntry] = []
        for template in TemplateLibrary.all where selectedTemplates.contains(template.id) {
            do {
                let range = dateRanges[template.id]
                let result = try applier.apply(
                    template,
                    selection: .init(),
                    startDate: range?.start,
                    endDate: range?.end
                )
                entries.append(QueueEntry(template: template, blocklist: result.blocklist))
            } catch {
                errorText = error.localizedDescription
                return
            }
        }
        appsQueueEntries = entries
        pickerIndex = 0
        applier.syncAfterApply()
        go(to: .apps)
    }

    private func advancePicker() {
        pickerIndex += 1
        if pickerIndex >= appsQueueEntries.count {
            go(to: .done)
        }
    }

    // MARK: - Finish

    private func finish() {
        finishAttempts += 1
        do {
            try AppSettingsStore(context: context).markOnboardingComplete()
            finishError = nil
            dismiss()
        } catch {
            // `markOnboardingComplete` already wrote the UserDefaults
            // backstop before throwing, so RootView will let the user reach
            // the app even though the SwiftData save failed. After the user
            // sees the error once, the next tap dismisses regardless.
            print("[Brick] markOnboardingComplete failed: \(error)")
            if finishAttempts >= 2 {
                dismiss()
                return
            }
            let nsError = error as NSError
            finishError = """
            Couldn't fully persist onboarding (\(nsError.domain) #\(nsError.code)) — \
            \(nsError.localizedDescription). Tap Continue anyway to enter the app.
            """
            if step != .done { step = .done }
        }
    }

    // MARK: - Auth

    private func requestAuth() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authRequested = true
            authError = nil
        } catch {
            authError = """
            Couldn't get Screen Time permission. Open Settings → Screen Time, \
            make sure Screen Time is on, then tap Grant permission again. \
            If you tap Don't Allow on the system dialog, return here and tap \
            Grant permission to retry.
            """
            authRequested = true
        }
    }
}
