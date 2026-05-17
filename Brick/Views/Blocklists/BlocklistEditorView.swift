import FamilyControls
import SwiftData
import SwiftUI

struct BlocklistEditorView: View {
    enum Mode {
        case create
        case edit(Blocklist)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String = ""
    @State private var selection: FamilyActivitySelection = .init()
    @State private var showingPicker = false
    @State private var errorMessage: String?
    @State private var showUnlockGate = false
    @State private var isUnlocked = false
    @State private var isLocked = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteGate = false
    @State private var pendingCascadeDelete: [String]?

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. Social, Deep Work", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .disabled(isBlockedByGate)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Apps & categories") {
                Button {
                    showingPicker = true
                } label: {
                    HStack {
                        Text("Select apps")
                        Spacer()
                        Text(summary).foregroundStyle(.secondary)
                    }
                }
                .familyActivityPicker(isPresented: $showingPicker, selection: $selection)
                .disabled(isBlockedByGate)
            }

            if isBlockedByGate {
                Section {
                    Text("This blocklist is currently enforcing a block. Unlock to edit it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if case .edit = mode {
                Section {
                    Button(role: .destructive) {
                        requestDelete()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete blocklist")
                            Spacer()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(trimmedName.isEmpty || isBlockedByGate)
            }
        }
        .onAppear(perform: load)
        .passcodeGate(
            title: "Edit active blocklist",
            reason: "This blocklist is currently enforcing a block. Enter your passcode to edit it.",
            isPresented: $showUnlockGate
        ) {
            isUnlocked = true
        }
        .passcodeGate(
            title: "Delete active blocklist",
            reason: "This blocklist is currently being enforced. Enter your passcode to delete it.",
            isPresented: $showDeleteGate
        ) {
            performDelete()
        }
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete(cascade: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let names = pendingCascadeDelete, !names.isEmpty {
                Text("Also deletes schedules: \(names.joined(separator: ", ")).")
            } else {
                Text("This can't be undone.")
            }
        }
    }

    private var isBlockedByGate: Bool {
        guard case .edit = mode else { return false }
        return isLocked && !isUnlocked
    }

    private var deleteConfirmTitle: String {
        if case .edit(let blocklist) = mode {
            return "Delete \"\(blocklist.name)\"?"
        }
        return "Delete blocklist?"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var summary: String {
        // See Blocklist.selectionSummary — picker double-populates token and
        // struct sets, so max() is the real count. (#31)
        let apps = max(selection.applicationTokens.count, selection.applications.count)
        let cats = max(selection.categoryTokens.count, selection.categories.count)
        let total = apps + cats
        return total == 0 ? "None" : "\(total) selected"
    }

    private func load() {
        if case .edit(let blocklist) = mode {
            name = blocklist.name
            selection = blocklist.selection
            isLocked = LockdownManager(context: context).isLocked(.editBlocklist(blocklist))
            if isLocked && !isUnlocked {
                showUnlockGate = true
            }
        }
    }

    private func requestDelete() {
        guard case .edit(let blocklist) = mode else { return }
        if LockdownManager(context: context).isLocked(.deleteBlocklist(blocklist)) && !isUnlocked {
            showDeleteGate = true
            return
        }
        performDelete()
    }

    private func performDelete(cascade: Bool = false) {
        guard case .edit(let blocklist) = mode else { return }
        let store = BlocklistStore(context: context)
        do {
            try store.delete(blocklist, cascade: cascade)
            dismiss()
        } catch BlocklistStoreError.referencedBySchedules(let names) {
            pendingCascadeDelete = names
            showDeleteConfirm = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let store = BlocklistStore(context: context)
        do {
            switch mode {
            case .create:
                try store.create(name: trimmedName, selection: selection)
            case .edit(let blocklist):
                try store.rename(blocklist, to: trimmedName)
                try store.updateSelection(blocklist, to: selection)
            }
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension BlocklistEditorView.Mode {
    var title: String {
        switch self {
        case .create: "New Blocklist"
        case .edit: "Edit Blocklist"
        }
    }
}
