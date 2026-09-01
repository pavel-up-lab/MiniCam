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
    @Published private(set) var isTransportBusy = false

    let playbackController = VLCPlaybackController()

    private let stepResolver = ArchiveStepResolver(liveSnapInterval: 3)

    private let profileStore: ProfileStore
    private let credentialStore: CredentialStore
    private(set) var cameraClient: HikvisionClient?
    private var pausedLiveDate: Date?
    private var liveArchiveRefreshTask: Task<Void, Never>?

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
            playLive()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось подключиться к камере."
            connectionState = .failed(message)
        }
    }

    func seek(to date: Date) {
        pausedLiveDate = nil
        stopLiveArchiveRefresh()
        if date >= Date().addingTimeInterval(-3) {
            playLive()
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

    func playLive() {
        pausedLiveDate = nil
        playbackController.playLive()
        startLiveArchiveRefresh()
    }

    func togglePlayback() {
        guard !isTransportBusy else { return }

        if playbackController.isPaused {
            guard let pausedLiveDate else {
                playbackController.resume()
                return
            }

            self.pausedLiveDate = nil
            isTransportBusy = true
            Task { [weak self] in
                guard let self else { return }
                await self.resumeLivePause(at: pausedLiveDate)
                self.isTransportBusy = false
            }
            return
        }

        if case .live = playbackController.state {
            pausedLiveDate = playbackController.currentDate
        } else {
            pausedLiveDate = nil
        }
        stopLiveArchiveRefresh()
        playbackController.pause()
    }

    func step(by offset: TimeInterval) {
        guard !isTransportBusy else { return }
        switch playbackController.state {
        case .live, .archive:
            break
        case .loading, .failed:
            return
        }

        let origin = playbackController.currentDate
        let shouldRefreshRecent: Bool
        if case .live = playbackController.state {
            shouldRefreshRecent = true
        } else if let lastEnd = recordingSegments.last?.end {
            shouldRefreshRecent = origin >= lastEnd.addingTimeInterval(-60)
        } else {
            shouldRefreshRecent = true
        }

        pausedLiveDate = nil
        stopLiveArchiveRefresh()
        isTransportBusy = true
        Task { [weak self] in
            guard let self else { return }
            var segments = self.recordingSegments
            if shouldRefreshRecent {
                let lookback = max(abs(offset) + 90, 120)
                segments = await self.refreshRecentRecordings(
                    from: origin.addingTimeInterval(-lookback)
                )
            }

            let destination = self.stepResolver.destination(
                from: origin,
                offset: offset,
                segments: segments,
                liveDate: Date()
            )

            switch destination {
            case .live:
                self.playLive()
            case let .archive(segment, date):
                self.playbackController.playArchive(segment: segment, at: date)
            case nil:
                break
            }
            self.isTransportBusy = false
        }
    }

    private func resumeLivePause(at date: Date) async {
        let segments = await refreshRecentRecordings(
            from: date.addingTimeInterval(-120)
        )

        if let segment = segments.first(where: { $0.contains(date) }) {
            playbackController.playArchive(segment: segment, at: date)
        } else if let next = segments.first(where: { $0.start > date }) {
            playbackController.playArchive(segment: next, at: next.start)
        } else {
            playbackController.resume()
        }
    }

    private func refreshRecentRecordings(from start: Date) async -> [RecordingSegment] {
        guard let cameraClient else { return recordingSegments }

        do {
            let recent = try await cameraClient.searchRecordings(from: start, to: Date())
            guard !recent.isEmpty else { return recordingSegments }

            let older = recordingSegments.filter { $0.end <= start }
            recordingSegments = (older + recent).sorted { $0.start < $1.start }
            archiveSegmentCount = recordingSegments.count
            return recordingSegments
        } catch {
            return recordingSegments
        }
    }

    private func startLiveArchiveRefresh() {
        liveArchiveRefreshTask?.cancel()
        liveArchiveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    return
                }

                guard let self else { return }
                guard
                    case .live = self.playbackController.state,
                    !self.playbackController.isPaused
                else {
                    return
                }

                _ = await self.refreshRecentRecordings(
                    from: Date().addingTimeInterval(-120)
                )
            }
        }
    }

    private func stopLiveArchiveRefresh() {
        liveArchiveRefreshTask?.cancel()
        liveArchiveRefreshTask = nil
    }

    private func continueArchive() {
        guard
            case let .archive(date) = playbackController.state,
            let currentIndex = recordingSegments.firstIndex(where: {
                $0.start <= date && date <= $0.end
            })
        else {
            playLive()
            return
        }

        let nextIndex = recordingSegments.index(after: currentIndex)
        guard recordingSegments.indices.contains(nextIndex) else {
            playLive()
            return
        }

        let next = recordingSegments[nextIndex]
        playbackController.playArchive(segment: next, at: next.start)
    }
}
