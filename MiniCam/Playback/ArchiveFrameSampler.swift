import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VLCKit

struct ArchiveFrameSample {
    let capturedAt: Date
    let image: CGImage
    let thumbnailJPEG: Data
}

@MainActor
final class ArchiveFrameSampler: NSObject {
    let videoView = VLCVideoView(frame: .zero)

    private static let playbackRate: Float = 2
    private static let captureInterval: TimeInterval = 0.5

    private struct PendingSnapshot {
        let capturedAt: Date
        let fileURL: URL
    }

    private let library: VLCLibrary
    private let player: VLCMediaPlayer
    private var activeSlice: ArchiveAnalysisSlice?
    private var continuation: CheckedContinuation<[ArchiveFrameSample], Error>?
    private var pendingSnapshot: PendingSnapshot?
    private var samples: [ArchiveFrameSample] = []
    private var nextCaptureOffset: TimeInterval = 0
    private var hasEnded = false
    private var timeoutTask: Task<Void, Never>?
    private var snapshotTimeoutTask: Task<Void, Never>?
    private let diagnostics = PlaybackDiagnostics.shared
    private var activeSessionID: String?

    override init() {
        let options = [
            "--quiet",
            "--no-video-title-show",
            "--no-audio",
            "--network-caching=300"
        ]
        library = VLCLibrary(options: options)
        VLCPlaybackDiagnosticLogger.install(
            on: library,
            diagnostics: PlaybackDiagnostics.shared,
            source: "archiveSampler"
        )
        player = VLCMediaPlayer(library: library)
        super.init()
        videoView.fillScreen = true
        player.drawable = videoView
        player.delegate = self
    }

    func samples(
        for slice: ArchiveAnalysisSlice,
        credentials: CameraCredentials
    ) async throws -> [ArchiveFrameSample] {
        guard continuation == nil else {
            throw ArchiveFrameSamplerError.busy
        }
        guard
            let sourceURL = URL(string: slice.segment.playbackURI),
            let playbackURL = HikvisionPlaybackURL.bounded(
                sourceURL,
                from: slice.start,
                to: slice.end
            )
        else {
            throw ArchiveFrameSamplerError.invalidPlaybackURL
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                activeSlice = slice
                samples = []
                nextCaptureOffset = 0
                hasEnded = false

                let media = VLCMedia(url: playbackURL)
                media.addOption(":no-audio")
                media.addOption(":network-caching=300")
                media.addOption(":rtsp-frame-buffer-size=2000000")
                media.addOption(":rtsp-user=\(credentials.username)")
                media.addOption(":rtsp-pwd=\(credentials.password)")
                player.media = media
                player.rate = Self.playbackRate
                let sessionID = "sampler-\(UUID().uuidString.prefix(8))"
                activeSessionID = sessionID
                diagnostics.sessionOpened(id: sessionID, owner: .archiveSampler)
                player.play()

                let duration = max(15, slice.end.timeIntervalSince(slice.start) + 8)
                timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(duration * 1_000_000_000)
                        )
                    } catch {
                        return
                    }
                    self?.complete(.failure(ArchiveFrameSamplerError.timedOut))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.complete(.failure(CancellationError()))
            }
        }
    }

    func stop() {
        complete(.failure(CancellationError()))
    }

    private func captureIfNeeded() {
        guard
            let activeSlice,
            pendingSnapshot == nil,
            player.hasVideoOut
        else {
            return
        }

        let elapsed = max(0, (player.time.value?.doubleValue ?? 0) / 1_000)
        guard elapsed >= nextCaptureOffset else { return }
        let captureDate = min(
            activeSlice.start.addingTimeInterval(elapsed),
            activeSlice.end
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minicam-analysis-\(UUID().uuidString).png")
        pendingSnapshot = PendingSnapshot(capturedAt: captureDate, fileURL: fileURL)
        player.saveVideoSnapshot(at: fileURL.path, withWidth: 1280, andHeight: 720)

        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            self?.snapshotTimedOut()
        }
    }

    private func finishSnapshot() {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil

        let currentElapsed = max(0, (player.time.value?.doubleValue ?? 0) / 1_000)
        nextCaptureOffset = nextCaptureTime(after: currentElapsed)

        Task { [weak self] in
            let sample = await Task.detached(priority: .utility) {
                Self.makeSample(from: snapshot)
            }.value
            try? FileManager.default.removeItem(at: snapshot.fileURL)
            guard let self else { return }
            if let sample {
                self.samples.append(sample)
            }
            if self.hasEnded {
                self.complete(.success(self.samples))
            } else {
                self.captureIfNeeded()
            }
        }
    }

    private func snapshotTimedOut() {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        snapshotTimeoutTask = nil
        try? FileManager.default.removeItem(at: snapshot.fileURL)
        let elapsed = max(0, (player.time.value?.doubleValue ?? 0) / 1_000)
        nextCaptureOffset = nextCaptureTime(after: elapsed)
        if hasEnded {
            complete(.success(samples))
        } else {
            captureIfNeeded()
        }
    }

    private func playbackEnded() {
        hasEnded = true
        if pendingSnapshot == nil {
            complete(.success(samples))
        }
    }

    private func nextCaptureTime(after elapsed: TimeInterval) -> TimeInterval {
        let interval = Self.captureInterval
        return (floor(elapsed / interval) + 1) * interval
    }

    private func playbackTimeChanged() {
        captureIfNeeded()
        guard let activeSlice else { return }
        let elapsed = max(0, (player.time.value?.doubleValue ?? 0) / 1_000)
        let duration = activeSlice.end.timeIntervalSince(activeSlice.start)
        if elapsed >= max(0, duration - 0.2) {
            playbackEnded()
        }
    }

    private func complete(_ result: Result<[ArchiveFrameSample], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        if let pendingSnapshot {
            try? FileManager.default.removeItem(at: pendingSnapshot.fileURL)
        }
        pendingSnapshot = nil
        activeSlice = nil
        hasEnded = false
        if let activeSessionID {
            diagnostics.sessionStopRequested(id: activeSessionID, owner: .archiveSampler)
        }
        player.stop()
        continuation.resume(with: result)
    }

    nonisolated private static func makeSample(
        from snapshot: PendingSnapshot
    ) -> ArchiveFrameSample? {
        guard
            let source = CGImageSourceCreateWithURL(snapshot.fileURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            image.width >= 1280,
            image.height >= 720
        else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ArchiveFrameSample(
            capturedAt: snapshot.capturedAt,
            image: image,
            thumbnailJPEG: output as Data
        )
    }
}

extension ArchiveFrameSampler: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch self.player.state {
            case .playing:
                self.diagnostics.record(
                    "archive-sampler.playing",
                    fields: ["session": self.activeSessionID ?? "none"]
                )
                self.player.rate = Self.playbackRate
                self.captureIfNeeded()
            case .ended:
                self.releaseActiveSession()
                self.playbackEnded()
            case .error:
                self.releaseActiveSession()
                self.complete(.failure(ArchiveFrameSamplerError.playbackFailed))
            case .stopped:
                self.releaseActiveSession()
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.playbackTimeChanged()
        }
    }

    nonisolated func mediaPlayerSnapshot(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.finishSnapshot()
        }
    }
}

private extension ArchiveFrameSampler {
    func releaseActiveSession() {
        guard let activeSessionID else { return }
        diagnostics.sessionReleased(id: activeSessionID, owner: .archiveSampler)
        self.activeSessionID = nil
    }
}

private enum ArchiveFrameSamplerError: LocalizedError {
    case busy
    case invalidPlaybackURL
    case playbackFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .busy:
            return "Анализатор архива уже занят."
        case .invalidPlaybackURL:
            return "Камера вернула неверную ссылку архива."
        case .playbackFailed:
            return "Не удалось прочитать новый фрагмент архива."
        case .timedOut:
            return "Камера слишком долго отдавала новый фрагмент архива."
        }
    }
}
