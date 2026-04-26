import FamilyControls
import SwiftData
import SwiftUI

/// First-launch flow: welcome → FC auth → passcode → templates → apps.
/// Presented as a `fullScreenCover` from RootView. Sets
/// `AppSettings.hasCompletedOnboarding = true` on the final step.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .welcome
    @State private var authRequested = false
    @State private var authError: String?
    @State private var selectedTemplates: Set<String> = []
    @State private var dateRanges: [String: DateRange] = [:]
    @State private var appsQueueEntries: [QueueEntry] = []
    @State private var pickerIndex: Int = 0
    @State private var pickerSelection: FamilyActivitySelection = .init()
    @State private var showingPicker = false
    @State private var errorText: String?

    enum Step: Int {
        case welcome, auth, passcode, templates, apps, done
    }

    struct DateRange: Equatable {
        var start: Date
        var end: Date
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcomeStep
                case .auth: authStep
                case .passcode: passcodeStep
                case .templates: templateStep
                case .apps: appsStep
                case .done: doneStep
                }
            }
            .padding()
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hand.raised.slash.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Welcome to Brick")
                .font(.largeTitle.bold())
            Text("Block distracting apps with real commitment. A passcode prevents easy disabling during active blocks.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Get started") { step = .auth }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var authStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Screen Time permission")
                .font(.title.bold())
            Text("Brick uses Apple's Screen Time framework to shield apps. You'll be asked to grant access next.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let authError {
                Text(authError).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
            Button(authRequested ? "Continue" : "Grant permission") {
                if authRequested {
                    step = .passcode
                } else {
                    Task { await requestAuth() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var passcodeStep: some View {
        PasscodeSetupView(purpose: .firstTime) {
            step = .templates
        }
    }

    private var templateStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Starter templates")
                .font(.title.bold())
            Text("Pick any that fit your routine. You can skip and add custom blocks later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(TemplateLibrary.all) { template in
                        templateRow(template)
                    }
                }
            }

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }

            HStack {
                Button("Skip") { finish() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(selectedTemplates.isEmpty ? "Continue" : "Pick apps") {
                    applyTemplatesAndAdvance()
                }
                .buttonStyle(.borderedProminent)
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick apps for \(current.blocklist.name)")
                    .font(.title2.bold())
                Text(current.template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Pick social, news, or anything you want shielded during this block. You can edit later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open app picker") {
                    pickerSelection = current.blocklist.selection
                    showingPicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Skip for now") { advancePicker() }
                    .buttonStyle(.bordered)
            }
            .familyActivityPicker(isPresented: $showingPicker, selection: $pickerSelection)
            .onChange(of: showingPicker) { _, presenting in
                if !presenting {
                    try? BlocklistStore(context: context)
                        .updateSelection(current.blocklist, to: pickerSelection)
                    advancePicker()
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're ready")
                .font(.largeTitle.bold())
            Text("Brick is active. Start a block now or let your schedules kick in.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Brick") { finish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    // MARK: - Template row

    @ViewBuilder
    private func templateRow(_ template: Template) -> some View {
        let isSelected = selectedTemplates.contains(template.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.headline)
                    Text(template.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
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
        step = .apps
    }

    private func advancePicker() {
        pickerIndex += 1
        if pickerIndex >= appsQueueEntries.count {
            step = .done
        }
    }

    // MARK: - Finish

    private func finish() {
        try? AppSettingsStore(context: context).markOnboardingComplete()
        dismiss()
    }

    // MARK: - Auth

    private func requestAuth() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .child)
            authRequested = true
            authError = nil
        } catch {
            authError = "Permission denied. You can grant it in Settings > Screen Time."
            authRequested = true
        }
    }
}
