import FamilyControls
import Foundation
import ManagedSettings

/// Seam for swapping the shield in tests. Production uses `ShieldManager`;
/// tests inject a recording implementation.
protocol ShieldApplying {
    func apply(union selection: FamilyActivitySelection)
    func apply(
        union selection: FamilyActivitySelection,
        exceptApps: Set<ApplicationToken>,
        exceptCategories: Set<ActivityCategoryToken>
    )
    func clear()
}

extension ShieldApplying {
    /// Convenience: apply with only an app-level exception, equivalent to
    /// the original API before category-break support.
    func apply(union selection: FamilyActivitySelection, except breakApps: Set<ApplicationToken>) {
        apply(union: selection, exceptApps: breakApps, exceptCategories: [])
    }
}

/// Thin wrapper around a single ManagedSettingsStore.
/// Applies shield = union of every active blocklist's selection.
struct ShieldManager: ShieldApplying {
    let store: ManagedSettingsStore

    init(storeName: ManagedSettingsStore.Name = .default) {
        self.store = ManagedSettingsStore(named: storeName)
    }

    func apply(union selection: FamilyActivitySelection) {
        apply(union: selection, exceptApps: [], exceptCategories: [])
    }

    /// Apply the union minus apps currently on a per-app break and minus
    /// categories currently on a category-level break. Lifting a category
    /// removes it from `applicationCategories` so apps shielded only via
    /// that category are released. Apps explicitly shielded *and* in a
    /// lifted category remain shielded — user intent was per-app + per-cat.
    func apply(
        union selection: FamilyActivitySelection,
        exceptApps: Set<ApplicationToken>,
        exceptCategories: Set<ActivityCategoryToken>
    ) {
        let apps = selection.applicationTokens.subtracting(exceptApps)
        let categories = selection.categoryTokens.subtracting(exceptCategories)
        let domains = selection.webDomainTokens

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: exceptApps)
        store.shield.webDomains = domains.isEmpty ? nil : domains
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
    }

    func clear() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }
}

extension FamilyActivitySelection {
    mutating func formUnion(_ other: FamilyActivitySelection) {
        applicationTokens.formUnion(other.applicationTokens)
        categoryTokens.formUnion(other.categoryTokens)
        webDomainTokens.formUnion(other.webDomainTokens)
    }

    static func union(_ selections: [FamilyActivitySelection]) -> FamilyActivitySelection {
        var combined = FamilyActivitySelection()
        for s in selections { combined.formUnion(s) }
        return combined
    }

    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }
}
