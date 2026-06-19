import Foundation

public struct Preferences: Codable, Equatable, Sendable {
    public var autoRestoreEnabled: Bool

    public init(
        autoRestoreEnabled: Bool = true
    ) {
        self.autoRestoreEnabled = autoRestoreEnabled
    }
}

public final class PreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "preferences"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Preferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? decoder.decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return preferences
    }

    public func save(_ preferences: Preferences) {
        guard let data = try? encoder.encode(preferences) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
