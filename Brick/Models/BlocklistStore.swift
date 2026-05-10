import FamilyControls
import Foundation
import SwiftData

enum BlocklistStoreError: LocalizedError {
    case emptyName
    case duplicateName(String)
    case referencedBySchedules([String])

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Name can't be empty."
        case .duplicateName(let name): return "A blocklist named \"\(name)\" already exists."
        case .referencedBySchedules(let names):
            let list = names.joined(separator: ", ")
            return "In use by: \(list)."
        }
    }
}

struct BlocklistStore {
    let context: ModelContext

    @discardableResult
    func create(name: String, selection: FamilyActivitySelection = .init()) throws -> Blocklist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BlocklistStoreError.emptyName }
        if try existsName(trimmed) { throw BlocklistStoreError.duplicateName(trimmed) }

        let blocklist = Blocklist(name: trimmed, selection: selection)
        context.insert(blocklist)
        try context.save()
        return blocklist
    }

    func rename(_ blocklist: Blocklist, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BlocklistStoreError.emptyName }
        guard trimmed != blocklist.name else { return }
        if try existsName(trimmed) { throw BlocklistStoreError.duplicateName(trimmed) }
        blocklist.name = trimmed
        try context.save()
    }

    func updateSelection(_ blocklist: Blocklist, to selection: FamilyActivitySelection) throws {
        blocklist.selection = selection
        try context.save()
        // Re-apply the shield right away. Otherwise the active block's
        // ManagedSettings store keeps the union it was given at interval
        // start (often empty if the user hadn't picked apps yet) until the
        // next DeviceActivity boundary fires, which can be hours.
        try? ScheduleEngine(context: context).applyCurrentUnion()
    }

    func delete(_ blocklist: Blocklist, cascade: Bool = false) throws {
        let referencing = try ScheduleStore(context: context).schedulesReferencing(blocklist)
        if !referencing.isEmpty && !cascade {
            throw BlocklistStoreError.referencedBySchedules(referencing.map(\.name))
        }
        let scheduleStore = ScheduleStore(context: context)
        for schedule in referencing {
            try scheduleStore.delete(schedule)
        }
        context.delete(blocklist)
        try context.save()
    }

    func all() throws -> [Blocklist] {
        let descriptor = FetchDescriptor<Blocklist>(
            sortBy: [SortDescriptor(\.createdDate, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func existsName(_ name: String) throws -> Bool {
        var descriptor = FetchDescriptor<Blocklist>(
            predicate: #Predicate { $0.name == name }
        )
        descriptor.fetchLimit = 1
        return try context.fetchCount(descriptor) > 0
    }
}
