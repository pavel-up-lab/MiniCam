import AppKit
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
    @Published private(set) var interfaceFontScale: InterfaceFontScale
    @Published private(set) var storageStatus: StorageStatus = .internalStorage
    @Published private(set) var isApplyingSettings = false
    @Published private(set) var currentExternalFolderURL: URL?
    @Published private(set) var screenshotFolderURL: URL
    @Published private(set) var currentCustomScreenshotFolderURL: URL?
    @Published private(set) var isScreenshotFolderFallback = false
    @Published private(set) var isExportingVideo = false
    @Published private(set) var videoExportProgress = 0.0
    @Published private(set) var isClearingMotionEvents = false

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
    private let screenshotFolderAccess = SecurityScopedFolderAccess()

    private let profileStore: ProfileStore
    private let credentialStore: CredentialStore
    private(set) var cameraClient: HikvisionClient?
    private var activeCredentials: CameraCredentials?
    private var pausedLiveDate: Date?
    private var archiveRefreshTask: Task<Void, Never>?
    private var archiveContinuationTask: Task<Void, Never>?
    private var motionEventCleanupTask: Task<Void, Never>?
    private var activeVideoExporter: VideoClipExporter?
    private var applicationTerminationObserver: NSObjectProtocol?
    private var isMaintainingMotionEvents = false
    private let playbackExperiment = ArchivePlaybackExperiment.current
    private let playbackDiagnostics = PlaybackDiagnostics.shared
    private var vlcDiagnosticLogger: VLCPlaybackDiagnosticLogger?

    init(
        profileStore: ProfileStore = ProfileStore(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        settingsStore: AppSettingsStore = AppSettingsStore()
    ) {
        let settings = settingsStore.load()
        let desktopURL = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
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
        interfaceFontScale = settings.interfaceFontScale
        screenshotFolderURL = desktopURL
        archivePreviewController = ArchivePreviewController(store: frameCacheStore)
        frameCacheRecorder = FrameCacheRecorder(store: frameCacheStore)
        motionAnalyzer = ArchiveMotionAnalyzer(
            frameCacheStore: frameCacheStore,
            store: motionEventStore
        )
        self.profileStore = profileStore
        self.credentialStore = credentialStore
        profile = profileStore.load()
        playbackDiagnostics.begin(experiment: playbackExperiment)
        vlcDiagnosticLogger = VLCPlaybackDiagnosticLogger.install(
            diagnostics: playbackDiagnostics
        )
        motionAnalyzer.setMotionTrackingEnabled(settings.isMotionTrackingEnabled)
        motionAnalyzer.setMotionEventRecordingMode(settings.motionEventRecordingMode)
        playbackController.playbackWillTransition = { [weak self] in
            self?.motionAnalyzer.suspendSampling()
        }
        playbackController.playbackTransitionDidFinish = { [weak self] in
            self?.motionAnalyzer.resumeSampling()
        }

        if let bookmark = settings.screenshotFolderBookmark {
            let resolvedURL = try? ExternalFolderBookmark.resolve(bookmark)
            currentCustomScreenshotFolderURL = resolvedURL
                ?? settings.screenshotFolderDisplayPath.map { URL(fileURLWithPath: $0) }
            if let resolvedURL {
                screenshotFolderAccess.replace(with: resolvedURL)
                if Self.isWritableDirectory(resolvedURL) {
                    screenshotFolderURL = resolvedURL
                } else {
                    screenshotFolderAccess.replace(with: nil)
                    isScreenshotFolderFallback = true
                }
            } else {
                isScreenshotFolderFallback = true
            }
        }

        var folderToRestore: URL?
        if let bookmark = settings.externalStorageBookmark {
            let resolvedURL = try? ExternalFolderBookmark.resolve(bookmark)
            currentExternalFolderURL = resolvedURL
                ?? settings.externalStorageDisplayPath.map { URL(fileURLWithPath: $0) }
            folderToRestore = currentExternalFolderURL
            externalFolderAccess.replace(with: resolvedURL)
        }

        applicationTerminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.activeVideoExporter?.cancel()
            self?.motionEventCleanupTask?.cancel()
        }

        let savedCredentials = try? credentialStore.load()
        let savedProfile = profile
        Task { [weak self] in
            guard let self else { return }
            if let folderToRestore {
                self.storageStatus = await self.storageCoordinator
                    .configureExternalFolder(folderToRestore)
            }
            self.startMotionEventCleanupSchedule()
            if let savedCredentials, !savedCredentials.isEmpty {
                await self.connect(profile: savedProfile, credentials: savedCredentials)
            }
        }
    }

    func applySettings(
        motionTrackingEnabled: Bool,
        interfaceFontScale: InterfaceFontScale,
        motionEventRecordingMode: MotionEventRecordingMode,
        motionEventRetention: MotionEventRetention,
        externalFolderURL: URL?,
        screenshotFolderURL: URL?
    ) async throws {
        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let previousExternalFolderURL = currentExternalFolderURL
        let screenshotSettings = try prepareScreenshotFolder(screenshotFolderURL)
        let storageSettings: (
            bookmark: Data?,
            displayPath: String?
        )
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
            storageSettings = (bookmark, externalFolderURL.path)
        } else {
            let status = await storageCoordinator.configureInternalStorage()
            guard case .internalStorage = status else {
                storageStatus = await restoreStorageSelection(previousExternalFolderURL)
                throw SettingsApplyError.storageMigrationFailed
            }
            storageStatus = status
            currentExternalFolderURL = nil
            externalFolderAccess.replace(with: nil)
            storageSettings = (nil, nil)
        }

        applyScreenshotFolder(screenshotFolderURL)
        let newSettings = AppSettings(
            isMotionTrackingEnabled: motionTrackingEnabled,
            interfaceFontScale: interfaceFontScale,
            motionEventRecordingMode: motionEventRecordingMode,
            motionEventRetention: motionEventRetention,
            lastMotionEventCleanupAt: appSettings.lastMotionEventCleanupAt,
            externalStorageBookmark: storageSettings.bookmark,
            externalStorageDisplayPath: storageSettings.displayPath,
            screenshotFolderBookmark: screenshotSettings.bookmark,
            screenshotFolderDisplayPath: screenshotSettings.displayPath
        )

        try settingsStore.save(newSettings)
        appSettings = newSettings
        self.interfaceFontScale = interfaceFontScale
        motionAnalyzer.setMotionTrackingEnabled(motionTrackingEnabled)
        motionAnalyzer.setMotionEventRecordingMode(motionEventRecordingMode)
    }

    func previewInterfaceFontScale(_ scale: InterfaceFontScale) {
        interfaceFontScale = scale
    }

    func cancelInterfaceFontScalePreview() {
        interfaceFontScale = appSettings.interfaceFontScale
    }

    func clearMotionEventHistory() async throws {
        guard !isMaintainingMotionEvents else { return }
        isMaintainingMotionEvents = true
        isClearingMotionEvents = true
        defer {
            isClearingMotionEvents = false
            isMaintainingMotionEvents = false
        }
        do {
            try await motionAnalyzer.clearEventHistory()
        } catch {
            throw SettingsApplyError.motionEventCleanupFailed
        }
    }

    func takeScreenshot() async throws -> URL {
        if let customFolder = currentCustomScreenshotFolderURL {
            if Self.isWritableDirectory(customFolder) {
                screenshotFolderURL = customFolder
                isScreenshotFolderFallback = false
            } else {
                screenshotFolderURL = Self.defaultScreenshotFolder
                isScreenshotFolderFallback = true
            }
        }
        return try await playbackController.saveCurrentFrame(to: screenshotFolderURL)
    }

    func exportVideoClip(from start: Date, to end: Date) async throws -> URL {
        guard !isExportingVideo else {
            throw VideoClipExportError.exportAlreadyRunning
        }
        guard let credentials = activeCredentials else {
            throw CameraError.authenticationFailed
        }

        let selection = try VideoClipSelectionResolver().resolve(
            from: start,
            to: end,
            segments: recordingSegments
        )
        let outputFolder = try resolveMediaOutputFolder()
        let restorePoint = try makeVideoRestorePoint()
        let exporter = try VideoClipExporter()
        activeVideoExporter = exporter

        isExportingVideo = true
        videoExportProgress = 0
        cancelArchiveContinuation()
        isTransportBusy = true
        stopArchiveRefresh()
        motionAnalyzer.suspendSampling()
        frameCacheRecorder.stop()
        await playbackController.releaseForExternalTransport()

        let result: Result<URL, Error>
        do {
            let fileURL = try await exporter.export(
                selection: selection,
                credentials: credentials,
                to: outputFolder
            ) { [weak self] progress in
                self?.videoExportProgress = progress
            }
            result = .success(fileURL)
        } catch {
            result = .failure(error)
        }

        await restorePlayback(after: restorePoint)
        if let cameraClient, playbackExperiment.usesBackgroundPlayback {
            frameCacheRecorder.start(
                client: cameraClient,
                profile: profile,
                credentials: credentials
            )
        }
        startArchiveRefresh()
        isTransportBusy = false
        isExportingVideo = false
        videoExportProgress = 0
        activeVideoExporter = nil
        return try result.get()
    }

    private func prepareScreenshotFolder(
        _ folderURL: URL?
    ) throws -> (bookmark: Data?, displayPath: String?) {
        guard let folderURL else {
            return (nil, nil)
        }

        let didStartTemporaryAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartTemporaryAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        guard Self.isWritableDirectory(folderURL) else {
            throw SettingsApplyError.screenshotFolderUnavailable
        }
        let bookmark = try ExternalFolderBookmark.make(for: folderURL)
        return (bookmark, folderURL.path)
    }

    private func resolveMediaOutputFolder() throws -> URL {
        if let customFolder = currentCustomScreenshotFolderURL {
            guard Self.isWritableDirectory(customFolder) else {
                screenshotFolderURL = Self.defaultScreenshotFolder
                isScreenshotFolderFallback = true
                guard Self.isWritableDirectory(screenshotFolderURL) else {
                    throw VideoClipExportError.folderUnavailable
                }
                return screenshotFolderURL
            }
            screenshotFolderURL = customFolder
            isScreenshotFolderFallback = false
        }
        guard Self.isWritableDirectory(screenshotFolderURL) else {
            throw VideoClipExportError.folderUnavailable
        }
        return screenshotFolderURL
    }

    private func makeVideoRestorePoint() throws -> VideoPlaybackRestorePoint {
        switch playbackController.state {
        case .live:
            return VideoPlaybackRestorePoint(
                source: .live,
                date: playbackController.currentDate,
                wasPaused: playbackController.isPaused
            )
        case .archive:
            return VideoPlaybackRestorePoint(
                source: .archive,
                date: playbackController.currentDate,
                wasPaused: playbackController.isPaused
            )
        case .loading, .failed:
            throw VideoClipExportError.playbackUnavailable
        }
    }

    private func restorePlayback(after point: VideoPlaybackRestorePoint) async {
        if point.source == .live, !point.wasPaused {
            playLive()
            return
        }

        let segments = await refreshRecentRecordings(
            from: point.date.addingTimeInterval(-120)
        )
        if point.wasPaused {
            playbackController.pauseAfterNextFrame()
        }
        if let segment = segments.first(where: { $0.contains(point.date) }) {
            playbackController.playArchive(segment: segment, at: point.date)
        } else if let next = segments.first(where: { $0.start > point.date }) {
            playbackController.playArchive(segment: next, at: next.start)
        } else {
            playbackController.playLive()
        }
    }

    private func applyScreenshotFolder(_ folderURL: URL?) {
        guard let folderURL else {
            screenshotFolderAccess.replace(with: nil)
            currentCustomScreenshotFolderURL = nil
            screenshotFolderURL = Self.defaultScreenshotFolder
            isScreenshotFolderFallback = false
            return
        }

        screenshotFolderAccess.replace(with: folderURL)
        currentCustomScreenshotFolderURL = folderURL
        screenshotFolderURL = folderURL
        isScreenshotFolderFallback = false
    }

    private static var defaultScreenshotFolder: URL {
        FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static func isWritableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }
        let probe = url.appendingPathComponent(".minicam-screenshot-write-test")
        do {
            try Data([0]).write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            try? FileManager.default.removeItem(at: probe)
            return false
        }
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

        playbackDiagnostics.configureSensitiveValues([
            credentials.username,
            credentials.password
        ])

        frameCacheRecorder.stop()
        motionAnalyzer.stop()
        stopArchiveRefresh()
        cancelArchiveContinuation()
        activeCredentials = nil
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
            activeCredentials = credentials
            recordingSegments = segments.sorted { $0.start < $1.start }
            archiveSegmentCount = segments.count
            playbackController.configure(profile: profile, credentials: credentials)
            playbackController.archiveDidFinish = { [weak self] in
                self?.continueArchive()
            }
            connectionState = .connected(identity)
            isReady = true
            if playbackExperiment.usesBackgroundPlayback {
                motionAnalyzer.start(at: analysisStart, credentials: credentials)
                motionAnalyzer.enqueueNewArchive(from: recordingSegments)
            } else {
                playbackDiagnostics.record("background-playback.disabled")
            }
            if playbackExperiment.usesFFplay {
                playbackDiagnostics.record("foreground-playback.skipped")
            } else {
                playLive()
            }
            startArchiveRefresh()
            if playbackExperiment.usesBackgroundPlayback {
                frameCacheRecorder.start(
                    client: client,
                    profile: profile,
                    credentials: credentials
                )
            }
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
        if playbackExperiment.usesFFplay {
            playbackDiagnostics.record("foreground-playback.skipped")
            return
        }
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

    private func startMotionEventCleanupSchedule() {
        motionEventCleanupTask?.cancel()
        motionEventCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.performScheduledMotionEventCleanupIfDue()
                do {
                    try await Task.sleep(nanoseconds: 3_600_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func performScheduledMotionEventCleanupIfDue(
        at referenceDate: Date = Date()
    ) async {
        guard !isApplyingSettings, !isMaintainingMotionEvents else { return }
        guard let lastCleanupAt = appSettings.lastMotionEventCleanupAt else {
            var initializedSettings = appSettings
            initializedSettings.lastMotionEventCleanupAt = referenceDate
            guard (try? settingsStore.save(initializedSettings)) != nil else { return }
            appSettings = initializedSettings
            return
        }
        guard referenceDate.timeIntervalSince(lastCleanupAt) >= 86_400 else { return }

        isMaintainingMotionEvents = true
        defer { isMaintainingMotionEvents = false }
        let cutoff = referenceDate.addingTimeInterval(-appSettings.motionEventRetention.duration)
        do {
            try await motionAnalyzer.pruneEventHistory(olderThan: cutoff)
            var updatedSettings = appSettings
            updatedSettings.lastMotionEventCleanupAt = referenceDate
            try settingsStore.save(updatedSettings)
            appSettings = updatedSettings
        } catch {
#if DEBUG
            print("[MotionEvents] scheduled cleanup failed: \(error)")
#endif
        }
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

private struct VideoPlaybackRestorePoint {
    enum Source: Equatable {
        case live
        case archive
    }

    let source: Source
    let date: Date
    let wasPaused: Bool
}

enum SettingsApplyError: LocalizedError {
    case externalFolderUnavailable
    case storageMigrationFailed
    case screenshotFolderUnavailable
    case motionEventCleanupFailed

    var errorDescription: String? {
        switch self {
        case .externalFolderUnavailable:
            return "Не удалось записать данные в выбранную папку. Настройки не сохранены."
        case .storageMigrationFailed:
            return "Не удалось безопасно перенести все данные. Настройки не изменены."
        case .screenshotFolderUnavailable:
            return "Не удалось записать скриншот в выбранную папку."
        case .motionEventCleanupFailed:
            return "Не удалось полностью очистить историю событий. Попробуйте ещё раз."
        }
    }
}
