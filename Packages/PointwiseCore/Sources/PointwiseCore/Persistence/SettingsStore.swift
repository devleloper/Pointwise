import Foundation

/// Persists `AppSettings` as versioned JSON in `UserDefaults`.
public struct SettingsStore: Sendable {
    static let currentVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var settings: AppSettings
    }

    private let suiteName: String?
    private let key: String

    /// `suiteName` selects a separate defaults domain, used by tests.
    public init(suiteName: String? = nil, key: String = "settings") {
        self.suiteName = suiteName
        self.key = key
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Returns stored settings, or defaults when nothing is stored or the data is unreadable.
    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return AppSettings()
        }
        return envelope.settings
    }

    public func save(_ settings: AppSettings) {
        let envelope = Envelope(version: Self.currentVersion, settings: settings)
        // Encoding plain value types cannot fail.
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: key)
    }
}
