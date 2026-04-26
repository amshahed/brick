import FamilyControls
import Foundation
import ManagedSettings

/// Thin wrapper around a single ManagedSettingsStore.
/// Applies shield = union of every active blocklist's selection.
struct ShieldManager {
    let store: ManagedSettingsStore

    init(storeName: ManagedSettingsStore.Name = .default) {
        self.store = ManagedSettingsStore(named: storeName)
    }

    func apply(union selection: FamilyActivitySelection) {
        apply(union: selection, except: [])
    }

    /// Apply the union minus a set of app tokens currently on a break. The
    /// break apps are subtracted from `applications` and added to category
    /// exceptions, so an app shielded only via its category is also released.
    func apply(union selection: FamilyActivitySelection, except breakApps: Set<ApplicationToken>) {
        let apps = selection.applicationTokens.subtracting(breakApps)
        let categories = selection.categoryTokens
        let domains = selection.webDomainTokens

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: breakApps)
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
