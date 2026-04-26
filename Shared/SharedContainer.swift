import Foundation

enum SharedContainer {
    static let appGroup = "group.com.amshahedhasan.brick"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            fatalError("[Brick] App Group container unavailable: \(appGroup)")
        }
        return url
    }

    static var storeURL: URL {
        containerURL.appendingPathComponent("Brick.sqlite")
    }
}
