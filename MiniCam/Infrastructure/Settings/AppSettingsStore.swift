import Foundation

final class AppSettingsStore {
    private let defaults: UserDefaults
    private let key = "appSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: key)
    }
}
