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

    /// Idempotent: if a blocklist with the template's name already exists,
    /// reuse it (and its schedule, if present) rather than creating a
    /// "Deep Work 2" duplicate. Re-running onboarding therefore doesn't
    /// silently spawn parallel blocklists.
    ///
    /// - If `selection` has any tokens, it overwrites the existing blocklist's
    ///   selection. Empty selection leaves the existing one intact.
    /// - The schedule's start/end dates are updated for date-bounded templates.
    @discardableResult
    func apply(
        _ template: Template,
        selection: FamilyActivitySelection = .init(),
        startDate: Date? = nil,
        endDate: Date? = nil
    ) throws -> Result {
        let blocklists = BlocklistStore(context: context)
        let existing = try blocklists.all().first { $0.name == template.name }

        let blocklist: Blocklist
        if let existing {
            blocklist = existing
            if !selection.isEmpty {
                try blocklists.updateSelection(existing, to: selection)
            }
        } else {
            blocklist = try blocklists.create(name: template.name, selection: selection)
        }

        // Reuse an existing schedule that targets this blocklist; otherwise
        // create one. We insert directly rather than via ScheduleStore so we
        // don't trigger `ScheduleEngine.sync()` for every applied template —
        // the caller syncs once after applying all templates.
        let blocklistID = blocklist.persistentModelID
        let existingSchedule = try context.fetch(FetchDescriptor<Schedule>())
            .first { $0.blocklist?.persistentModelID == blocklistID }
        let schedule: Schedule
        if let existingSchedule {
            existingSchedule.weekdayMask = template.weekdayMask
            existingSchedule.startMinute = template.startMinute
            existingSchedule.endMinute = template.endMinute
            existingSchedule.startDate = template.requiresDateRange ? startDate : nil
            existingSchedule.endDate = template.requiresDateRange ? endDate : nil
            existingSchedule.enabled = true
            schedule = existingSchedule
        } else {
            schedule = Schedule(
                name: template.name,
                blocklist: blocklist,
                weekdayMask: template.weekdayMask,
                startMinute: template.startMinute,
                endMinute: template.endMinute,
                startDate: template.requiresDateRange ? startDate : nil,
                endDate: template.requiresDateRange ? endDate : nil
            )
            context.insert(schedule)
        }
        try context.save()
        return Result(blocklist: blocklist, schedule: schedule)
    }

    /// Run after `apply(_:)` calls to register the newly-inserted schedules
    /// with DeviceActivity. Fails silently — callers in the onboarding UI
    /// can't reasonably show an error here.
    func syncAfterApply() {
        try? ScheduleEngine(context: context).sync()
    }
}
