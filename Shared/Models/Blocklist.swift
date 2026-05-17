import FamilyControls
import Foundation
import SwiftData

@Model
final class Blocklist {
    @Attribute(.unique) var name: String
    var activitySelectionData: Data
    var createdDate: Date

    init(name: String, selection: FamilyActivitySelection = .init(), createdDate: Date = .now) {
        self.name = name
        self.activitySelectionData = Self.encode(selection)
        self.createdDate = createdDate
    }

    var selection: FamilyActivitySelection {
        get { Self.decode(activitySelectionData) }
        set { activitySelectionData = Self.encode(newValue) }
    }

    var selectionSummary: String {
        let s = selection
        // Under .individual auth, FamilyActivityPicker populates both the
        // opaque-token set and the Application/Category/WebDomain struct set
        // with the same picks — summing the two doubles the count. Take the
        // max so we still get the right number if either set is empty. (#31)
        let apps = max(s.applicationTokens.count, s.applications.count)
        let cats = max(s.categoryTokens.count, s.categories.count)
        let domains = max(s.webDomainTokens.count, s.webDomains.count)

        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
        if domains > 0 { parts.append("\(domains) domain\(domains == 1 ? "" : "s")") }
        return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
    }

    private static func encode(_ selection: FamilyActivitySelection) -> Data {
        (try? PropertyListEncoder().encode(selection)) ?? Data()
    }

    private static func decode(_ data: Data) -> FamilyActivitySelection {
        guard !data.isEmpty,
              let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return decoded
    }
}
