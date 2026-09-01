import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VLCKit

@MainActor
final class FrameCacheRecorder: NSObject {
    let videoView = VLCVideoView(frame: .zero)

    private enum SourceMode: Equatable {
        case idle
        case http
        case rtspFallback
    }

    private struct PendingSnapshot {
        let id: UUID
        let capturedAt: Date
        let fileURL: URL
    }

    private struct ProcessedFrame: Sendable {
        let data: Data
        let width: Int
        let height: Int
    }

    private let player: VLCMediaPlayer
    private let store: FrameCacheStore
    private var captureTask: Task<Void, Never>?
    private var snapshotTimeoutTask: Task<Void, Never>?
    private var pendingSnapshot: PendingSnapshot?
    private var sourceMode = SourceMode.idle
    private var consecutiveHTTPFailures = 0

    init(store: FrameCacheStore) {
        self.store = store
        player = VLCMediaPlayer(options: [
            "--quiet",
            "--no-video-title-show",
            "--network-caching=300",
            "--live-caching=300"
        ])
        super.init()
        videoView.fillScreen = true
        player.drawable = videoView
        player.delegate = self
    }

    func start(
        client: HikvisionClient,
        profile: CameraProfile,
        credentials: CameraCredentials
    ) {
        stop()
        sourceMode = .http
        consecutiveHTTPFailures = 0

        captureTask = Task { [weak self, client] in
            while !Task.isCancelled {
                guard let self else { return }
                switch self.sourceMode {
                case .idle:
                    return
                case .http:
                    await self.captureHTTPFrame(
                        client: client,
                        profile: profile,
                        credentials: credentials
                    )
                case .rtspFallback:
                    self.captureRTSPFrameIfPossible()
                }

                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        sourceMode = .idle
        captureTask?.cancel()
        captureTask = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        discardPendingSnapshot()
        player.stop()
    }

    private func captureHTTPFrame(
        client: HikvisionClient,
        profile: CameraProfile,
        credentials: CameraCredentials
    ) async {
        let sourceData: Data
        do {
            sourceData = try await client.fetchCurrentSnapshot()
        } catch {
            consecutiveHTTPFailures += 1
            if consecutiveHTTPFailures >= 3 {
                activateRTSPFallback(profile: profile, credentials: credentials)
            }
            return
        }

        let frame = await Task.detached(priority: .utility) {
            Self.makeCacheFrame(from: sourceData)
        }.value
        guard let frame else {
            activateRTSPFallback(profile: profile, credentials: credentials)
            return
        }

        consecutiveHTTPFailures = 0
        try? await store.storeJPEG(frame.data, capturedAt: Date())
#if DEBUG
        print("[FrameCache] HTTP \(frame.width)x\(frame.height) \(frame.data.count) bytes")
#endif
    }

    private func activateRTSPFallback(
        profile: CameraProfile,
        credentials: CameraCredentials
    ) {
        guard sourceMode != .rtspFallback else { return }
        guard let url = profile.liveStreamURL(stream: .main) else {
            sourceMode = .idle
            return
        }

        sourceMode = .rtspFallback
        let media = VLCMedia(url: url)
        media.addOption(":no-audio")
        media.addOption(":network-caching=300")
        media.addOption(":rtsp-frame-buffer-size=2000000")
        media.addOption(":rtsp-user=\(credentials.username)")
        media.addOption(":rtsp-pwd=\(credentials.password)")
        player.media = media
        player.play()
    }

    private func captureRTSPFrameIfPossible() {
        guard player.hasVideoOut, pendingSnapshot == nil else { return }

        let id = UUID()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minicam-frame-\(id.uuidString).png")
        pendingSnapshot = PendingSnapshot(
            id: id,
            capturedAt: Date(),
            fileURL: fileURL
        )
        player.saveVideoSnapshot(at: fileURL.path, withWidth: 1280, andHeight: 720)

        snapshotTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            guard self?.pendingSnapshot?.id == id else { return }
            self?.discardPendingSnapshot()
        }
    }

    private func finishRTSPSnapshot() {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil

        Task { [store] in
            let frame: ProcessedFrame? = await Task.detached(priority: .utility) { () -> ProcessedFrame? in
                defer { try? FileManager.default.removeItem(at: snapshot.fileURL) }
                guard let data = try? Data(contentsOf: snapshot.fileURL) else { return nil }
                return Self.makeCacheFrame(from: data)
            }.value
            guard let frame else { return }
            try? await store.storeJPEG(frame.data, capturedAt: snapshot.capturedAt)
#if DEBUG
            print("[FrameCache] RTSP \(frame.width)x\(frame.height) \(frame.data.count) bytes")
#endif
        }
    }

    private func discardPendingSnapshot() {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        try? FileManager.default.removeItem(at: snapshot.fileURL)
    }

    nonisolated private static func makeCacheFrame(from sourceData: Data) -> ProcessedFrame? {
        guard
            let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
            let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
            sourceImage.width >= 1280,
            sourceImage.height >= 720
        else {
            return nil
        }

        let horizontalScale = 1280.0 / Double(sourceImage.width)
        let verticalScale = 720.0 / Double(sourceImage.height)
        let scale = min(1, max(horizontalScale, verticalScale))
        let width = Int((Double(sourceImage.width) * scale).rounded())
        let height = Int((Double(sourceImage.height) * scale).rounded())

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options = [
            kCGImageDestinationLossyCompressionQuality: 0.6
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return ProcessedFrame(data: output as Data, width: width, height: height)
    }
}

extension FrameCacheRecorder: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerSnapshot(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.finishRTSPSnapshot()
        }
    }
}
