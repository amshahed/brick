import SwiftData
import SwiftUI

struct BlocklistsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Blocklist.createdDate, order: .forward) private var blocklists: [Blocklist]
    @State private var showingNewEditor = false
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
                BrickEmptyState(
                    eyebrow: "Blocklists",
                    title: "Group apps\nyou want to block.",
                    body: "Build named bundles of apps and categories, then point a schedule or one-off block at one. Or start from a template in Schedules.",
                    primaryActionLabel: "New blocklist",
                    primaryAction: { showingNewEditor = true }
                )
            } else {
                List {
                    ForEach(blocklists) { blocklist in
                        ZStack {
                            NavigationLink(value: blocklist) { EmptyView() }
                                .opacity(0)
                            BlocklistRow(blocklist: blocklist)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: Theme.Space.lg, bottom: 6, trailing: Theme.Space.lg))
                        // No `role: .destructive` — see SchedulesListView
                        // for the rationale. Short version: destructive
                        // swipes animate the row out before the passcode
                        // gate resolves, leaving the row hidden but the
                        // data intact when the user cancels.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                attemptDelete(blocklist)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Blocklists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewEditor = true } label: {
                    Label("New blocklist", systemImage: "plus")
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

    private func attemptDelete(_ blocklist: Blocklist) {
        let lockdown = LockdownManager(context: context)
        if lockdown.isLocked(.deleteBlocklist(blocklist)) {
            pendingActiveDelete = blocklist
            showDeleteGate = true
        } else {
            performDelete(blocklist)
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
