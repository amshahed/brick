import Foundation

enum SharedContainer {
    static let appGroup = "group.com.amshahedhasan.brick"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            return url
        }
        // Simulator/test contexts where the App Group entitlement isn't
        // applied: fall back to the app sandbox. Main app and extensions
        // won't share state in this mode, but the process can still launch.
        let fallback = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Brick", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: fallback, withIntermediateDirectories: true
        )
        return fallback
    }

    static var storeURL: URL {
        containerURL.appendingPathComponent("Brick.sqlite")
    }
}

/// App-group–scoped UserDefaults so the main app and extensions share
/// state (e.g. the debug "fast break timings" toggle). `UserDefaults.standard`
/// is per-process and won't propagate across the boundary. Falls back to
/// `.standard` when the App Group entitlement isn't applied (simulator,
/// some test contexts) so callers don't have to special-case nil.
enum SharedDefaults {
    static var shared: UserDefaults {
        UserDefaults(suiteName: SharedContainer.appGroup) ?? .standard
    }
}
