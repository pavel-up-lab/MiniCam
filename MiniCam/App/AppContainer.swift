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
    @Published private(set) var recordingSegments: [RecordingSegment] = []
    @Published private(set) var isReady = false

    let playbackController = VLCPlaybackController()

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

        if let credentials = try? credentialStore.load(), !credentials.isEmpty {
            let savedProfile = profile
            Task { [weak self] in
                await self?.connect(profile: savedProfile, credentials: credentials)
            }
        }
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
            recordingSegments = segments.sorted { $0.start < $1.start }
            archiveSegmentCount = segments.count
            playbackController.configure(profile: profile, credentials: credentials)
            playbackController.archiveDidFinish = { [weak self] in
                self?.continueArchive()
            }
            connectionState = .connected(identity)
            isReady = true
            playbackController.playLive()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось подключиться к камере."
            connectionState = .failed(message)
        }
    }

    func seek(to date: Date) {
        if date >= Date().addingTimeInterval(-3) {
            playbackController.playLive()
            return
        }

        if let segment = recordingSegments.first(where: { $0.contains(date) }) {
            playbackController.playArchive(segment: segment, at: date)
            return
        }

        if let next = recordingSegments.first(where: { $0.start > date }) {
            playbackController.playArchive(segment: next, at: next.start)
        }
    }

    private func continueArchive() {
        guard
            case let .archive(date) = playbackController.state,
            let currentIndex = recordingSegments.firstIndex(where: {
                $0.start <= date && date <= $0.end
            })
        else {
            playbackController.playLive()
            return
        }

        let nextIndex = recordingSegments.index(after: currentIndex)
        guard recordingSegments.indices.contains(nextIndex) else {
            playbackController.playLive()
            return
        }

        let next = recordingSegments[nextIndex]
        playbackController.playArchive(segment: next, at: next.start)
    }
}
