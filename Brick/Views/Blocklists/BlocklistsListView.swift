import SwiftData
import SwiftUI

struct BlocklistsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Blocklist.createdDate, order: .forward) private var blocklists: [Blocklist]
    @State private var showingNewEditor = false
    @State private var showingTemplatePicker = false
    @State private var pendingDelete: PendingDelete?
    @State private var pendingActiveDelete: Blocklist?
    @State private var showDeleteGate = false

    struct PendingDelete: Identifiable {
        let id = UUID()
        let blocklist: Blocklist
        let scheduleNames: [String]
    }

    var body: some View {
        Group {
            if blocklists.isEmpty {
                ContentUnavailableView {
                    Label("No blocklists yet", systemImage: "square.stack")
                } description: {
                    Text("Create a blocklist to group the apps you want to block.")
                } actions: {
                    VStack(spacing: 8) {
                        Button("New blocklist") { showingNewEditor = true }
                            .buttonStyle(.borderedProminent)
                        Button("Start from template") { showingTemplatePicker = true }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                List {
                    ForEach(blocklists) { blocklist in
                        NavigationLink(value: blocklist) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(blocklist.name).font(.headline)
                                Text(blocklist.selectionSummary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Blocklists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingNewEditor = true } label: {
                        Label("New blocklist", systemImage: "plus")
                    }
                    Button { showingTemplatePicker = true } label: {
                        Label("Start from template", systemImage: "sparkles")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: Blocklist.self) { blocklist in
            BlocklistEditorView(mode: .edit(blocklist))
        }
        .sheet(isPresented: $showingNewEditor) {
            NavigationStack {
                BlocklistEditorView(mode: .create)
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerSheet()
        }
        .alert(item: $pendingDelete) { pending in
            Alert(
                title: Text("Delete \"\(pending.blocklist.name)\"?"),
                message: Text("Also deletes schedules: \(pending.scheduleNames.joined(separator: ", "))."),
                primaryButton: .destructive(Text("Delete all")) {
                    try? BlocklistStore(context: context).delete(pending.blocklist, cascade: true)
                },
                secondaryButton: .cancel()
            )
        }
        .passcodeGate(
            title: "Delete active blocklist",
            reason: "This blocklist is currently being enforced. Enter your passcode to delete it.",
            isPresented: $showDeleteGate
        ) {
            if let blocklist = pendingActiveDelete {
                performDelete(blocklist)
            }
            pendingActiveDelete = nil
        }
    }

    private func delete(at offsets: IndexSet) {
        let lockdown = LockdownManager(context: context)
        for index in offsets {
            let blocklist = blocklists[index]
            if lockdown.isLocked(.deleteBlocklist(blocklist)) {
                pendingActiveDelete = blocklist
                showDeleteGate = true
            } else {
                performDelete(blocklist)
            }
        }
    }

    private func performDelete(_ blocklist: Blocklist) {
        let store = BlocklistStore(context: context)
        do {
            try store.delete(blocklist)
        } catch BlocklistStoreError.referencedBySchedules(let names) {
            pendingDelete = PendingDelete(blocklist: blocklist, scheduleNames: names)
        } catch {
            // Silent on other errors; could surface a toast.
        }
    }
}
