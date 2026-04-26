import FamilyControls
import Foundation
import SwiftData

/// Creates a Blocklist + Schedule pair from a Template. Used by onboarding
/// and the "Start from template" entry. Blocklist is created with the given
/// `FamilyActivitySelection` (empty by default); the user can fill it in
/// later. Name conflicts get "-2", "-3" suffixes.
struct TemplateApplier {
    let context: ModelContext

    struct Result {
        let blocklist: Blocklist
        let schedule: Schedule
    }

    @discardableResult
    func apply(
        _ template: Template,
        selection: FamilyActivitySelection = .init(),
        startDate: Date? = nil,
        endDate: Date? = nil
    ) throws -> Result {
        let blocklists = BlocklistStore(context: context)

        let name = try uniqueName(base: template.name, store: blocklists)
        let blocklist = try blocklists.create(name: name, selection: selection)

        // Insert the Schedule directly rather than going through
        // ScheduleStore.create so we don't trigger `ScheduleEngine.sync()`
        // for every applied template — the caller syncs once after applying
        // all templates.
        let schedule = Schedule(
            name: name,
            blocklist: blocklist,
            weekdayMask: template.weekdayMask,
            startMinute: template.startMinute,
            endMinute: template.endMinute,
            startDate: template.requiresDateRange ? startDate : nil,
            endDate: template.requiresDateRange ? endDate : nil
        )
        context.insert(schedule)
        try context.save()
        return Result(blocklist: blocklist, schedule: schedule)
    }

    /// Run after `apply(_:)` calls to register the newly-inserted schedules
    /// with DeviceActivity. Fails silently — callers in the onboarding UI
    /// can't reasonably show an error here.
    func syncAfterApply() {
        try? ScheduleEngine(context: context).sync()
    }

    private func uniqueName(base: String, store: BlocklistStore) throws -> String {
        let existing = Set(try store.all().map(\.name))
        if !existing.contains(base) { return base }
        for suffix in 2...99 {
            let candidate = "\(base) \(suffix)"
            if !existing.contains(candidate) { return candidate }
        }
        return "\(base) \(UUID().uuidString.prefix(4))"
    }
}
