import FamilyControls
import SwiftData
import SwiftUI

/// Browse templates post-onboarding to scaffold a new blocklist + schedule.
/// After picking a template (and a date range when required), calls
/// `TemplateApplier` and dismisses. Unlike onboarding, this flow leaves the
/// app picker to the user via the blocklists editor.
struct TemplatePickerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Template?
    @State private var startDate: Date = .now
    @State private var endDate: Date = .now.addingTimeInterval(7 * 24 * 3600)
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(TemplateLibrary.all) { template in
                        Button {
                            selected = template
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name).font(.headline)
                                    Text(template.description)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected?.id == template.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let template = selected, template.requiresDateRange {
                    Section("Date range") {
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("Start from template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: apply)
                        .disabled(selected == nil)
                }
            }
        }
    }

    private func apply() {
        guard let template = selected else { return }
        let applier = TemplateApplier(context: context)
        do {
            _ = try applier.apply(
                template,
                selection: .init(),
                startDate: template.requiresDateRange ? startDate : nil,
                endDate: template.requiresDateRange ? endDate : nil
            )
            applier.syncAfterApply()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
