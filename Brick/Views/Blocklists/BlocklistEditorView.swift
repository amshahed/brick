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
    @State private var lockChecked = false

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
        }
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
    }

    private var isBlockedByGate: Bool {
        guard case .edit = mode else { return false }
        guard lockChecked else { return false }
        return !isUnlocked
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var summary: String {
        let apps = selection.applicationTokens.count + selection.applications.count
        let cats = selection.categoryTokens.count + selection.categories.count
        let total = apps + cats
        return total == 0 ? "None" : "\(total) selected"
    }

    private func load() {
        if case .edit(let blocklist) = mode {
            name = blocklist.name
            selection = blocklist.selection
            let locked = LockdownManager(context: context).isLocked(.editBlocklist(blocklist))
            lockChecked = true
            if locked && !isUnlocked {
                showUnlockGate = true
            }
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
