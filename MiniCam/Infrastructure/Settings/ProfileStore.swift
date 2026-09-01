import Foundation

final class ProfileStore {
    private let defaults: UserDefaults
    private let key = "cameraProfile"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CameraProfile {
        guard
            let data = defaults.data(forKey: key),
            let profile = try? JSONDecoder().decode(CameraProfile.self, from: data)
        else {
            return .defaultCamera
        }

        return profile
    }

    func save(_ profile: CameraProfile) throws {
        defaults.set(try JSONEncoder().encode(profile), forKey: key)
    }
}

