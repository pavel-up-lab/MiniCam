import Foundation

final class AppSettingsStore {
    private let defaults: UserDefaults
    private let key = "appSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(referenceDate: Date = Date()) -> AppSettings {
        guard
            let data = defaults.data(forKey: key),
            var settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            var settings = AppSettings.default
            settings.lastMotionEventCleanupAt = referenceDate
            try? save(settings)
            return settings
        }
        if settings.lastMotionEventCleanupAt == nil {
            settings.lastMotionEventCleanupAt = referenceDate
            try? save(settings)
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: key)
    }
}
