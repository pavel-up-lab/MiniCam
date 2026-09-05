import AppKit
import Foundation
import VLCKit

@MainActor
final class VLCPlaybackController: NSObject, ObservableObject {
    @Published private(set) var state: PlaybackState = .loading(nil)
    @Published private(set) var currentDate = Date()
    @Published private(set) var isPaused = false
    @Published private(set) var frameRevision = 0
    @Published private(set) var transitionID = 0
    @Published private(set) var readyTransitionID = 0
    @Published private(set) var isSavingScreenshot = false

    let videoView = VLCVideoView(frame: .zero)
    var archiveDidFinish: (() -> Void)?
    var playbackWillTransition: (() -> Void)?
    var playbackTransitionDidFinish: (() -> Void)?

    private var library: VLCLibrary
    private var player: VLCMediaPlayer
    private var playerUsesDefaultFramePolicy: Bool
    private var playerUsesSoftwareDecoding: Bool
    private var profile: CameraProfile?
    private var credentials: CameraCredentials?
    private var activeSegment: RecordingSegment?
    private var activePlaybackStart: Date?
    private var isAwaitingFirstFrame = false
    private var hasLoadedMedia = false
    private var startedTransitionID = 0
    private var transitionQueue = PlaybackTransitionQueue<PlaybackRequest>()
    private var liveRequestGate = LivePlaybackRequestGate()
    private var stopFallbackTask: Task<Void, Never>?
    private var releaseDelayTask: Task<Void, Never>?
    private var videoOutputProbeTask: Task<Void, Never>?
    private var pendingScreenshot: PendingScreenshot?
    private var pauseWhenReady = false
    private let diagnostics = PlaybackDiagnostics.shared
    private var playerDiagnosticID: String
    private var activeSessionID: String?
    private var timeDiscontinuityDetector = PlaybackTimeDiscontinuityDetector(
        toleranceMilliseconds: 5
    )
    private var receivedTimeUpdateForTransition = false
    private var desiredDefaultFramePolicy = false
    private var desiredSoftwareDecoding = false
    private let playbackExperiment = ArchivePlaybackExperiment.current
    private let ffplayDiagnostic = FFplayArchiveDiagnostic()

    private static let cameraReleaseDelayNanoseconds: UInt64 = 400_000_000

    private struct PlaybackRequest {
        let url: URL
        let lowLatency: Bool
        let transitionID: Int
    }

    private struct PendingScreenshot {
        let fileURL: URL
        let continuation: CheckedContinuation<URL, Error>
        let timeoutTask: Task<Void, Never>
    }

    override init() {
        let instance = Self.makePlayer(
            softwareDecoding: false,
            defaultFramePolicy: false
        )
        library = instance.library
        player = instance.player
        playerUsesDefaultFramePolicy = false
        playerUsesSoftwareDecoding = false
        playerDiagnosticID = Self.makePlayerDiagnosticID()
        super.init()
        attachCurrentPlayer()
    }

    func configure(profile: CameraProfile, credentials: CameraCredentials) {
        self.profile = profile
        self.credentials = credentials
        diagnostics.configureSensitiveValues([
            credentials.username,
            credentials.password
        ])
        liveRequestGate.reset()
    }

    @discardableResult
    func playLive() -> Int? {
        ffplayDiagnostic.stop()
        guard let profile, let url = profile.liveStreamURL() else {
            state = .failed(.invalidAddress)
            return nil
        }
        guard liveRequestGate.shouldAccept() else {
            return transitionID > 0 ? transitionID : nil
        }

        activeSegment = nil
        activePlaybackStart = nil
        isPaused = false
        currentDate = Date()
        state = .loading(nil)
        return play(url: url, lowLatency: true)
    }

    @discardableResult
    func playArchive(segment: RecordingSegment, at date: Date) -> Int? {
        guard
            let sourceURL = URL(string: segment.playbackURI),
            let url = HikvisionPlaybackURL.starting(sourceURL, at: date)
        else {
            state = .failed(.incompatibleArchive)
            return nil
        }

        if let transport = ffplayTransport {
            return playArchiveInFFplay(
                sourceURL: url,
                segment: segment,
                date: date,
                transport: transport
            )
        }

        liveRequestGate.reset()

        activeSegment = segment
        activePlaybackStart = date
        isPaused = false
        currentDate = date
        state = .loading(date)
        return play(url: url, lowLatency: false)
    }

    func stop() {
        ffplayDiagnostic.stop()
        isPaused = false
        pauseWhenReady = false
        transitionQueue.reset()
        stopFallbackTask?.cancel()
        stopFallbackTask = nil
        releaseDelayTask?.cancel()
        releaseDelayTask = nil
        videoOutputProbeTask?.cancel()
        videoOutputProbeTask = nil
        requestCurrentSessionStop()
        player.stop()
    }

    func pauseAfterNextFrame() {
        pauseWhenReady = true
    }

    func releaseForExternalTransport() async {
        playbackWillTransition?()
        let releasedAt = currentDate
        isPaused = false
        pauseWhenReady = false
        transitionQueue.reset()
        stopFallbackTask?.cancel()
        stopFallbackTask = nil
        releaseDelayTask?.cancel()
        releaseDelayTask = nil
        videoOutputProbeTask?.cancel()
        videoOutputProbeTask = nil
        requestCurrentSessionStop()
        player.stop()
        hasLoadedMedia = false
        activeSegment = nil
        activePlaybackStart = nil
        state = .loading(releasedAt)

        do {
            try await Task.sleep(nanoseconds: 900_000_000)
        } catch {
            return
        }
        replacePlayer()
    }

    private func playArchiveInFFplay(
        sourceURL: URL,
        segment: RecordingSegment,
        date: Date,
        transport: FFplayArchiveTransport
    ) -> Int? {
        guard let credentials else {
            state = .failed(.cameraUnavailable)
            return nil
        }
        playbackWillTransition?()
        transitionID += 1
        let requestedTransitionID = transitionID
        state = .loading(date)
        ffplayDiagnostic.stop()

        Task { [weak self] in
            guard let self else { return }
            await self.releaseForExternalTransport()
            guard requestedTransitionID == self.transitionID else { return }
            do {
                try self.ffplayDiagnostic.start(
                    sourceURL: sourceURL,
                    credentials: credentials,
                    transport: transport
                )
                self.activeSegment = segment
                self.activePlaybackStart = date
                self.currentDate = date
                self.state = .archive(date)
                self.readyTransitionID = requestedTransitionID
                self.playbackTransitionDidFinish?()
            } catch {
                self.diagnostics.record("ffplay.launch-failed")
                self.state = .failed(.cameraUnavailable)
                self.playbackTransitionDidFinish?()
            }
        }
        return requestedTransitionID
    }

    private var ffplayTransport: FFplayArchiveTransport? {
        switch playbackExperiment {
        case .ffplayUDP:
            return .udp
        case .ffplayTCP:
            return .tcp
        case .baseline, .defaultFramePolicy, .foregroundOnly, .softwareDecoding:
            return nil
        }
    }

    func pause() {
        guard !isPaused else { return }
        switch state {
        case .live, .archive:
            player.pause()
            isPaused = true
        case .loading, .failed:
            break
        }
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        player.play()
    }

    func saveCurrentFrame(to directory: URL) async throws -> URL {
        guard pendingScreenshot == nil else {
            throw ScreenshotError.alreadySaving
        }
        guard player.hasVideoOut else {
            throw ScreenshotError.frameUnavailable
        }
        switch state {
        case .live, .archive:
            break
        case .loading, .failed:
            throw ScreenshotError.frameUnavailable
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = uniqueScreenshotURL(in: directory)
        isSavingScreenshot = true

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
                self?.finishScreenshot(.failure(ScreenshotError.timedOut))
            }
            pendingScreenshot = PendingScreenshot(
                fileURL: fileURL,
                continuation: continuation,
                timeoutTask: timeoutTask
            )
            player.saveVideoSnapshot(
                at: fileURL.path,
                withWidth: 0,
                andHeight: 0
            )
        }
    }

    private func play(url: URL, lowLatency: Bool) -> Int {
        playbackWillTransition?()
        transitionID += 1
        let startedTransitionID = transitionID
        isAwaitingFirstFrame = true
        receivedTimeUpdateForTransition = false
        diagnostics.record(
            "playback.transition",
            fields: [
                "decoder": playbackExperiment.usesSoftwareDecoding(lowLatency: lowLatency)
                    ? "software"
                    : "default",
                "frame-policy": playbackExperiment.usesDefaultFramePolicy(lowLatency: lowLatency)
                    ? "default"
                    : "keep-late",
                "stream": lowLatency ? "live" : "archive",
                "transition": String(startedTransitionID),
                "transport": lowLatency ? "tcp" : "udp"
            ]
        )
        let request = PlaybackRequest(
            url: url,
            lowLatency: lowLatency,
            transitionID: startedTransitionID
        )

        desiredSoftwareDecoding = playbackExperiment.usesSoftwareDecoding(
            lowLatency: lowLatency
        )
        desiredDefaultFramePolicy = playbackExperiment.usesDefaultFramePolicy(
            lowLatency: lowLatency
        )
        if
            !hasLoadedMedia,
            playerUsesSoftwareDecoding != desiredSoftwareDecoding
                || playerUsesDefaultFramePolicy != desiredDefaultFramePolicy
        {
            replacePlayer()
        }

        let action = transitionQueue.schedule(request, playerNeedsStop: hasLoadedMedia)
        switch action {
        case .startNow:
            start(request)
        case .stopPlayer:
            requestCurrentSessionStop()
            player.stop()
            scheduleStopFallback()
        case .wait:
            break
        }
        return startedTransitionID
    }

    private func start(_ request: PlaybackRequest) {
        guard request.transitionID == transitionID else { return }
        startedTransitionID = request.transitionID
        hasLoadedMedia = true
        let sessionID = playerDiagnosticID
        activeSessionID = sessionID
        diagnostics.sessionOpened(id: sessionID, owner: .main)
        let media = VLCMedia(url: request.url)
        if request.lowLatency {
            media.addOption(":rtsp-tcp")
        }
        media.addOption(request.lowLatency ? ":network-caching=500" : ":network-caching=750")
        media.addOption(":rtsp-frame-buffer-size=2000000")

        if let credentials {
            media.addOption(":rtsp-user=\(credentials.username)")
            media.addOption(":rtsp-pwd=\(credentials.password)")
        }

        player.media = media
        diagnostics.record(
            "playback.play-requested",
            fields: [
                "player": playerDiagnosticID,
                "stream": request.lowLatency ? "live" : "archive",
                "transition": String(request.transitionID),
                "transport": request.lowLatency ? "tcp" : "udp"
            ]
        )
        player.play()
        startVideoOutputProbe(transitionID: request.transitionID)
    }

    private func scheduleStopFallback() {
        stopFallbackTask?.cancel()
        stopFallbackTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
            } catch {
                return
            }
            self?.scheduleReleaseCompletion()
        }
    }

    private func scheduleReleaseCompletion() {
        guard transitionQueue.isWaitingForStop else { return }
        stopFallbackTask?.cancel()
        stopFallbackTask = nil
        guard releaseDelayTask == nil else { return }

        releaseDelayTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: Self.cameraReleaseDelayNanoseconds
                )
            } catch {
                return
            }
            self?.finishStopping()
        }
    }

    private func finishStopping() {
        stopFallbackTask?.cancel()
        stopFallbackTask = nil
        releaseDelayTask?.cancel()
        releaseDelayTask = nil
        guard let request = transitionQueue.finishStopping() else {
            return
        }
        hasLoadedMedia = false
        replacePlayer()
        start(request)
    }

    private static func makePlayer(
        softwareDecoding: Bool,
        defaultFramePolicy: Bool
    ) -> (
        library: VLCLibrary,
        player: VLCMediaPlayer
    ) {
        var options = [
            "--no-video-title-show",
            "--no-snapshot-preview",
            "--network-caching=500",
            "--live-caching=500"
        ]
        if !defaultFramePolicy {
            options.append("--no-drop-late-frames")
            options.append("--no-skip-frames")
        }
        if softwareDecoding {
            options.append("--codec=avcodec,none")
            options.append("--avcodec-hw=none")
        }
        let library = VLCLibrary(options: options)
        VLCPlaybackDiagnosticLogger.install(
            on: library,
            diagnostics: PlaybackDiagnostics.shared,
            source: "main"
        )
        return (library, VLCMediaPlayer(library: library))
    }

    private func attachCurrentPlayer() {
        videoView.fillScreen = true
        player.drawable = videoView
        player.delegate = self
    }

    private func replacePlayer() {
        let previousPlayer = player
        let previousPlayerID = playerDiagnosticID
        previousPlayer.delegate = nil
        previousPlayer.drawable = nil
        releaseCurrentSession()
        diagnostics.record(
            "playback.player-detached",
            fields: ["player": previousPlayerID]
        )
        let instance = Self.makePlayer(
            softwareDecoding: desiredSoftwareDecoding,
            defaultFramePolicy: desiredDefaultFramePolicy
        )
        library = instance.library
        player = instance.player
        playerUsesDefaultFramePolicy = desiredDefaultFramePolicy
        playerUsesSoftwareDecoding = desiredSoftwareDecoding
        playerDiagnosticID = Self.makePlayerDiagnosticID()
        attachCurrentPlayer()
        diagnostics.record(
            "playback.player-replaced",
            fields: [
                "decoder": playerUsesSoftwareDecoding ? "software" : "default",
                "frame-policy": playerUsesDefaultFramePolicy ? "default" : "keep-late",
                "new": playerDiagnosticID,
                "previous": previousPlayerID
            ]
        )
    }

    private static func makePlayerDiagnosticID() -> String {
        "main-\(UUID().uuidString.prefix(8))"
    }

    private func requestCurrentSessionStop() {
        guard let activeSessionID else { return }
        diagnostics.sessionStopRequested(id: activeSessionID, owner: .main)
    }

    private func releaseCurrentSession() {
        guard let activeSessionID else { return }
        diagnostics.sessionReleased(id: activeSessionID, owner: .main)
        self.activeSessionID = nil
    }

    private func startVideoOutputProbe(transitionID: Int) {
        videoOutputProbeTask?.cancel()
        videoOutputProbeTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                guard transitionID == self.transitionID else { return }
                if
                    self.receivedTimeUpdateForTransition,
                    self.player.hasVideoOut,
                    self.videoView.hasVideo
                {
                    self.diagnostics.record(
                        "playback.video-output",
                        fields: [
                            "delay-ms": String(Int(Date().timeIntervalSince(startedAt) * 1_000)),
                            "player": self.playerDiagnosticID,
                            "transition": String(transitionID)
                        ]
                    )
                    return
                }
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return
                }
            }
            self.diagnostics.record(
                "playback.video-output-timeout",
                fields: [
                    "player": self.playerDiagnosticID,
                    "player-video": String(self.player.hasVideoOut),
                    "time-update": String(self.receivedTimeUpdateForTransition),
                    "view-video": String(self.videoView.hasVideo),
                    "transition": String(transitionID)
                ]
            )
        }
    }

    private func uniqueScreenshotURL(in directory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let stem = "MiniCam_\(formatter.string(from: Date()))"
        var candidate = directory.appendingPathComponent("\(stem).png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-\(suffix).png")
            suffix += 1
        }
        return candidate
    }

    private func finishScreenshot(_ result: Result<URL, Error>) {
        guard let pendingScreenshot else { return }
        self.pendingScreenshot = nil
        pendingScreenshot.timeoutTask.cancel()
        isSavingScreenshot = false

        switch result {
        case let .success(fileURL):
            guard
                let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                size > 0
            else {
                try? FileManager.default.removeItem(at: fileURL)
                pendingScreenshot.continuation.resume(
                    throwing: ScreenshotError.emptyFile
                )
                return
            }
            pendingScreenshot.continuation.resume(returning: fileURL)
        case let .failure(error):
            try? FileManager.default.removeItem(at: pendingScreenshot.fileURL)
            pendingScreenshot.continuation.resume(throwing: error)
        }
    }
}

extension VLCPlaybackController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        guard let source = notification.object as? VLCMediaPlayer else { return }
        let sourceID = ObjectIdentifier(source)
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard ObjectIdentifier(self.player) == sourceID else { return }

            switch self.player.state {
            case .stopped:
                self.diagnostics.record(
                    "playback.stopped",
                    fields: [
                        "player": self.playerDiagnosticID,
                        "transition": String(self.transitionID)
                    ]
                )
                if !self.transitionQueue.isWaitingForStop {
                    self.releaseCurrentSession()
                }
                self.scheduleReleaseCompletion()
            case .playing:
                self.diagnostics.record(
                    "playback.playing",
                    fields: [
                        "player": self.playerDiagnosticID,
                        "transition": String(self.transitionID)
                    ]
                )
                if let segment = self.activeSegment {
                    self.state = .archive(self.currentDate.clamped(to: segment.start...segment.end))
                } else {
                    self.state = .live
                }
            case .ended:
                self.hasLoadedMedia = false
                self.releaseCurrentSession()
                if self.activeSegment != nil {
                    self.archiveDidFinish?()
                }
            case .error:
                self.hasLoadedMedia = false
                self.releaseCurrentSession()
                self.isPaused = false
                self.state = .failed(.cameraUnavailable)
                self.playbackTransitionDidFinish?()
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        guard let source = notification.object as? VLCMediaPlayer else { return }
        let sourceID = ObjectIdentifier(source)
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard ObjectIdentifier(self.player) == sourceID else { return }
            guard self.startedTransitionID == self.transitionID else {
                return
            }
            self.receivedTimeUpdateForTransition = true
            let playbackMilliseconds = self.player.time.value?.int64Value ?? 0
            if let discontinuity = self.timeDiscontinuityDetector.observe(
                milliseconds: playbackMilliseconds,
                transitionID: self.transitionID
            ) {
                self.diagnostics.record(
                    "playback.time-backward",
                    fields: [
                        "current-ms": String(discontinuity.currentMilliseconds),
                        "previous-ms": String(discontinuity.previousMilliseconds),
                        "transition": String(discontinuity.transitionID)
                    ]
                )
            }
            if
                self.isAwaitingFirstFrame
            {
                self.isAwaitingFirstFrame = false
                self.frameRevision += 1
                self.readyTransitionID = self.transitionID
                self.playbackTransitionDidFinish?()
                if self.pauseWhenReady {
                    self.pauseWhenReady = false
                    self.player.pause()
                    self.isPaused = true
                }
#if DEBUG
                print("[Playback] first frame revision=\(self.frameRevision)")
#endif
            }
            if
                let segment = self.activeSegment,
                let playbackStart = self.activePlaybackStart
            {
                let elapsed = self.player.time.value?.doubleValue ?? 0
                self.currentDate = playbackStart.addingTimeInterval(elapsed / 1_000)
                self.state = .archive(self.currentDate.clamped(to: segment.start...segment.end))
            } else {
                self.currentDate = Date()
            }
        }
    }

    nonisolated func mediaPlayerSnapshot(_ notification: Notification) {
        guard let source = notification.object as? VLCMediaPlayer else { return }
        let sourceID = ObjectIdentifier(source)
        Task { @MainActor [weak self] in
            guard let self, let pendingScreenshot = self.pendingScreenshot else { return }
            guard ObjectIdentifier(self.player) == sourceID else { return }
            self.finishScreenshot(.success(pendingScreenshot.fileURL))
        }
    }
}

enum ScreenshotError: LocalizedError {
    case alreadySaving
    case frameUnavailable
    case timedOut
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .alreadySaving:
            return "Предыдущий скриншот ещё сохраняется."
        case .frameUnavailable:
            return "Дождитесь появления видеокадра."
        case .timedOut:
            return "Кадр не удалось сохранить вовремя. Попробуйте ещё раз."
        case .emptyFile:
            return "VLCKit создал пустой файл скриншота."
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
