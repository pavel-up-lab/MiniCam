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

    private let player: VLCMediaPlayer
    private var profile: CameraProfile?
    private var credentials: CameraCredentials?
    private var activeSegment: RecordingSegment?
    private var activePlaybackStart: Date?
    private var isAwaitingFirstFrame = false
    private var hasActiveTransitionEnteredPlaying = false
    private var pendingScreenshot: PendingScreenshot?

    private struct PendingScreenshot {
        let fileURL: URL
        let continuation: CheckedContinuation<URL, Error>
        let timeoutTask: Task<Void, Never>
    }

    override init() {
        player = VLCMediaPlayer(options: [
            "--no-video-title-show",
            "--no-drop-late-frames",
            "--no-skip-frames",
            "--network-caching=500",
            "--live-caching=500"
        ])
        super.init()
        videoView.fillScreen = true
        player.drawable = videoView
        player.delegate = self
    }

    func configure(profile: CameraProfile, credentials: CameraCredentials) {
        self.profile = profile
        self.credentials = credentials
    }

    @discardableResult
    func playLive() -> Int? {
        guard let profile, let url = profile.liveStreamURL() else {
            state = .failed(.invalidAddress)
            return nil
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

        activeSegment = segment
        activePlaybackStart = date
        isPaused = false
        currentDate = date
        state = .loading(date)
        return play(url: url, lowLatency: false)
    }

    func stop() {
        isPaused = false
        player.stop()
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
        transitionID += 1
        let startedTransitionID = transitionID
        player.stop()
        isAwaitingFirstFrame = true
        hasActiveTransitionEnteredPlaying = false
        let media = VLCMedia(url: url)
        media.addOption(lowLatency ? ":network-caching=500" : ":network-caching=750")

        if let credentials {
            media.addOption(":rtsp-user=\(credentials.username)")
            media.addOption(":rtsp-pwd=\(credentials.password)")
        }

        player.media = media
        player.play()
        return startedTransitionID
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
        Task { @MainActor [weak self] in
            guard let self else { return }

            switch self.player.state {
            case .playing:
                self.hasActiveTransitionEnteredPlaying = true
                if let segment = self.activeSegment {
                    self.state = .archive(self.currentDate.clamped(to: segment.start...segment.end))
                } else {
                    self.state = .live
                }
            case .ended:
                if self.activeSegment != nil {
                    self.archiveDidFinish?()
                }
            case .error:
                self.isPaused = false
                self.state = .failed(.cameraUnavailable)
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if
                self.isAwaitingFirstFrame,
                self.hasActiveTransitionEnteredPlaying,
                self.player.state == .playing
            {
                self.isAwaitingFirstFrame = false
                self.frameRevision += 1
                self.readyTransitionID = self.transitionID
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
        Task { @MainActor [weak self] in
            guard let self, let pendingScreenshot = self.pendingScreenshot else { return }
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
