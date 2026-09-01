import Foundation

@MainActor
final class AppContainer: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case checking
        case connected(DeviceIdentity)
        case failed(String)
    }

    @Published private(set) var profile: CameraProfile
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var archiveSegmentCount = 0
    @Published private(set) var isReady = false

    private let profileStore: ProfileStore
    private let credentialStore: CredentialStore
    private(set) var cameraClient: HikvisionClient?

    init(
        profileStore: ProfileStore = ProfileStore(),
        credentialStore: CredentialStore = KeychainCredentialStore()
    ) {
        self.profileStore = profileStore
        self.credentialStore = credentialStore
        profile = profileStore.load()
    }

    func connect(profile: CameraProfile, credentials: CameraCredentials) async {
        guard profile.httpBaseURL != nil, !credentials.isEmpty else {
            connectionState = .failed("Заполните адрес, имя пользователя и пароль.")
            return
        }

        connectionState = .checking
        let client = HikvisionClient(profile: profile, credentials: credentials)

        do {
            let identity = try await client.checkConnection()
            let archiveStart = Date().addingTimeInterval(-36 * 60 * 60)
            let segments = try await client.searchRecordings(from: archiveStart, to: Date())
            try profileStore.save(profile)
            try credentialStore.save(credentials)

            self.profile = profile
            cameraClient = client
            archiveSegmentCount = segments.count
            connectionState = .connected(identity)
            isReady = true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось подключиться к камере."
            connectionState = .failed(message)
        }
    }
}
