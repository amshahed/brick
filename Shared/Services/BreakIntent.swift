import Foundation

/// Handoff payload from ShieldAction extension → main app. Written to an
/// App Group file because ShieldAction extensions cannot open URLs.
struct BreakIntent: Codable, Equatable {
    let appTokenData: Data
    let createdAt: Date

    static let freshness: TimeInterval = 60

    static var fileURL: URL {
        SharedContainer.containerURL
            .appendingPathComponent("Intents/break.plist")
    }

    var isFresh: Bool {
        Date.now.timeIntervalSince(createdAt) <= Self.freshness
    }

    static func write(appTokenData: Data, at instant: Date = .now) throws {
        let intent = BreakIntent(appTokenData: appTokenData, createdAt: instant)
        let data = try PropertyListEncoder().encode(intent)
        let url = fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Reads the pending intent, deletes the file, and returns the payload
    /// only if still fresh. A stale intent is silently discarded.
    @discardableResult
    static func consume() -> BreakIntent? {
        let url = fileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        defer { try? fm.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url),
              let intent = try? PropertyListDecoder().decode(BreakIntent.self, from: data),
              intent.isFresh else { return nil }
        return intent
    }

    /// Discard any pending intent without consuming it — e.g. when the user
    /// dismisses the shield with "OK" after previously tapping "Take a break".
    static func clearPending() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// `brick://break?token=<base64url>` — optional URL entry point.
    static func fromURL(_ url: URL) -> BreakIntent? {
        guard url.scheme == "brick", url.host == "break",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let tokenItem = comps.queryItems?.first(where: { $0.name == "token" }),
              let encoded = tokenItem.value,
              let data = Data(base64Encoded: encoded.paddedForBase64())
        else { return nil }
        return BreakIntent(appTokenData: data, createdAt: .now)
    }
}

private extension String {
    func paddedForBase64() -> String {
        let remainder = count % 4
        return remainder == 0 ? self : self + String(repeating: "=", count: 4 - remainder)
    }
}
