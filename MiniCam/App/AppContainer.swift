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
    @Published private(set) var appSettings: AppSettings
    @Published private(set) var storageStatus: StorageStatus = .internalStorage
    @Published private(set) var isApplyingSettings = false
    @Published private(set) var currentExternalFolderURL: URL?

    let playbackController = VLCPlaybackController()
    let archivePreviewController: ArchivePreviewController
    let frameCacheRecorder: FrameCacheRecorder
    let motionAnalyzer: ArchiveMotionAnalyzer

    private let stepResolver = ArchiveStepResolver(liveSnapInterval: 3)
    private let continuationResolver = ArchiveContinuationResolver(
        minimumRemainingDuration: 0.5,
        resumeOffset: 0.001
    )
    private let frameCacheStore: FrameCacheStore
    private let storageCoordinator: StorageCoordinator
    private let settingsStore: AppSettingsStore
    private let externalFolderAccess = SecurityScopedFolderAccess()

    private let profileStore: ProfileStore
    private let credentialStore: CredentialStore
    private(set) var cameraClient: HikvisionClient?
    private var pausedLiveDate: Date?
    private var archiveRefreshTask: Task<Void, Never>?
    private var archiveContinuationTask: Task<Void, Never>?

    init(
        profileStore: ProfileStore = ProfileStore(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        settingsStore: AppSettingsStore = AppSettingsStore()
    ) {
        let settings = settingsStore.load()
        let internalRoot = StorageCoordinator.defaultInternalRoot
        let roots = StorageRootProvider(initialRoot: internalRoot)
        let storageCoordinator = StorageCoordinator(
            internalRoot: internalRoot,
            roots: roots
        )
        let frameCacheStore = FrameCacheStore(rootProvider: roots)
        let motionEventStore = MotionEventStore(rootProvider: roots)
        self.frameCacheStore = frameCacheStore
        self.storageCoordinator = storageCoordinator
        self.settingsStore = settingsStore
        appSettings = settings
        archivePreviewController = ArchivePreviewController(store: frameCacheStore)
        frameCacheRecorder = FrameCacheRecorder(store: frameCacheStore)
        motionAnalyzer = ArchiveMotionAnalyzer(
            frameCacheStore: frameCacheStore,
            store: motionEventStore
        )
        self.profileStore = profileStore
        self.credentialStore = credentialStore
        profile = profileStore.load()
        motionAnalyzer.setMotionTrackingEnabled(settings.isMotionTrackingEnabled)

        var folderToRestore: URL?
        if let bookmark = settings.externalStorageBookmark {
            let resolvedURL = try? ExternalFolderBookmark.resolve(bookmark)
            currentExternalFolderURL = resolvedURL
                ?? settings.externalStorageDisplayPath.map { URL(fileURLWithPath: $0) }
            folderToRestore = currentExternalFolderURL
            externalFolderAccess.replace(with: resolvedURL)
        }

        let savedCredentials = try? credentialStore.load()
        let savedProfile = profile
        Task { [weak self] in
            guard let self else { return }
            if let folderToRestore {
                self.storageStatus = await self.storageCoordinator
                    .configureExternalFolder(folderToRestore)
            }
            if let savedCredentials, !savedCredentials.isEmpty {
                await self.connect(profile: savedProfile, credentials: savedCredentials)
            }
        }
    }

    func applySettings(
        motionTrackingEnabled: Bool,
        externalFolderURL: URL?
    ) async throws {
        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let previousExternalFolderURL = currentExternalFolderURL
        let newSettings: AppSettings
        if let externalFolderURL {
            let bookmark = try ExternalFolderBookmark.make(for: externalFolderURL)
            externalFolderAccess.replace(with: externalFolderURL)
            let status = await storageCoordinator.configureExternalFolder(externalFolderURL)
            guard case .externalStorage = status else {
                externalFolderAccess.replace(with: previousExternalFolderURL)
                storageStatus = await restoreStorageSelection(previousExternalFolderURL)
                throw SettingsApplyError.externalFolderUnavailable
            }
            storageStatus = status
            currentExternalFolderURL = externalFolderURL
            newSettings = AppSettings(
                isMotionTrackingEnabled: motionTrackingEnabled,
                externalStorageBookmark: bookmark,
                externalStorageDisplayPath: externalFolderURL.path
            )
        } else {
            let status = await storageCoordinator.configureInternalStorage()
            guard case .internalStorage = status else {
                storageStatus = await restoreStorageSelection(previousExternalFolderURL)
                throw SettingsApplyError.storageMigrationFailed
            }
            storageStatus = status
            currentExternalFolderURL = nil
            externalFolderAccess.replace(with: nil)
            newSettings = AppSettings(
                isMotionTrackingEnabled: motionTrackingEnabled,
                externalStorageBookmark: nil,
                externalStorageDisplayPath: nil
            )
        }

        try settingsStore.save(newSettings)
        appSettings = newSettings
        motionAnalyzer.setMotionTrackingEnabled(motionTrackingEnabled)
    }

    private func restoreStorageSelection(_ externalFolderURL: URL?) async -> StorageStatus {
        if let externalFolderURL {
            return await storageCoordinator.configureExternalFolder(externalFolderURL)
        }
        return await storageCoordinator.configureInternalStorage()
    }

    func connect(profile: CameraProfile, credentials: CameraCredentials) async {
        guard profile.httpBaseURL != nil, !credentials.isEmpty else {
            connectionState = .failed("Заполните адрес, имя пользователя и пароль.")
            return
        }

        frameCacheRecorder.stop()
        motionAnalyzer.stop()
        stopArchiveRefresh()
        cancelArchiveContinuation()
        archivePreviewController.cancelAndHide()
        connectionState = .checking
        let analysisStart = Date()
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
            motionAnalyzer.start(at: analysisStart, credentials: credentials)
            motionAnalyzer.enqueueNewArchive(from: recordingSegments)
            playLive()
            startArchiveRefresh()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось подключиться к камере."
            connectionState = .failed(message)
        }
    }

    func seek(to date: Date) {
        cancelArchiveContinuation()
        pausedLiveDate = nil
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
            return
        }

        isTransportBusy = true
        Task { [weak self] in
            guard let self else { return }
            let segments = await self.refreshRecentRecordings(
                from: date.addingTimeInterval(-120)
            )
            if let segment = segments.first(where: { $0.contains(date) }) {
                self.playbackController.playArchive(segment: segment, at: date)
            } else if let next = segments.first(where: { $0.start > date }) {
                self.playbackController.playArchive(segment: next, at: next.start)
            } else {
                self.playLive()
            }
            self.isTransportBusy = false
        }
    }

    func preview(at date: Date) {
        if date >= Date().addingTimeInterval(-3) {
            archivePreviewController.cancelAndHide()
            return
        }

        archivePreviewController.request(at: date)
    }

    func playLive() {
        cancelArchiveContinuation()
        pausedLiveDate = nil
        playbackController.playLive()
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
            motionAnalyzer.enqueueNewArchive(from: recordingSegments)
            return recordingSegments
        } catch {
            return recordingSegments
        }
    }

    private func startArchiveRefresh() {
        archiveRefreshTask?.cancel()
        archiveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    return
                }

                guard let self else { return }
                _ = await self.refreshRecentRecordings(
                    from: Date().addingTimeInterval(-120)
                )
                await self.refreshStorageAvailability()
            }
        }
    }

    private func refreshStorageAvailability() async {
        guard appSettings.externalStorageBookmark != nil else { return }
        storageStatus = await storageCoordinator.refreshExternalFolder()
    }

    private func stopArchiveRefresh() {
        archiveRefreshTask?.cancel()
        archiveRefreshTask = nil
    }

    private func continueArchive() {
        guard case let .archive(endedAt) = playbackController.state else {
            playLive()
            return
        }

        archiveContinuationTask?.cancel()
        isTransportBusy = true
        archiveContinuationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isTransportBusy = false
                self.archiveContinuationTask = nil
            }

            for attempt in 0..<3 {
                if attempt > 0 {
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000)
                    } catch {
                        return
                    }
                }

                let segments = await self.refreshRecentRecordings(
                    from: endedAt.addingTimeInterval(-120)
                )
                guard !Task.isCancelled else { return }

                if case let .archive(segment, date)? = self.continuationResolver.destination(
                    after: endedAt,
                    segments: segments
                ) {
                    self.playbackController.playArchive(segment: segment, at: date)
                    return
                }
            }

            self.playLive()
        }
    }

    private func cancelArchiveContinuation() {
        archiveContinuationTask?.cancel()
        archiveContinuationTask = nil
        isTransportBusy = false
    }
}

enum SettingsApplyError: LocalizedError {
    case externalFolderUnavailable
    case storageMigrationFailed

    var errorDescription: String? {
        switch self {
        case .externalFolderUnavailable:
            return "Не удалось записать данные в выбранную папку. Настройки не сохранены."
        case .storageMigrationFailed:
            return "Не удалось безопасно перенести все данные. Настройки не изменены."
        }
    }
}
