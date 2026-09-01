import AppKit
import Foundation
import VLCKit

@MainActor
final class VLCPlaybackController: NSObject, ObservableObject {
    @Published private(set) var state: PlaybackState = .loading(nil)
    @Published private(set) var currentDate = Date()

    let videoView = VLCVideoView(frame: .zero)
    var archiveDidFinish: (() -> Void)?

    private let player: VLCMediaPlayer
    private var profile: CameraProfile?
    private var credentials: CameraCredentials?
    private var activeSegment: RecordingSegment?

    override init() {
        player = VLCMediaPlayer(options: [
            "--no-video-title-show",
            "--rtsp-tcp",
            "--network-caching=150",
            "--live-caching=150"
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

    func playLive() {
        guard let profile, let url = profile.liveStreamURL() else {
            state = .failed(.invalidAddress)
            return
        }

        activeSegment = nil
        currentDate = Date()
        state = .loading(nil)
        play(url: url, lowLatency: true)
    }

    func playArchive(segment: RecordingSegment, at date: Date) {
        guard let url = URL(string: segment.playbackURI) else {
            state = .failed(.incompatibleArchive)
            return
        }

        activeSegment = segment
        currentDate = date
        state = .loading(date)
        play(url: url, lowLatency: false)

        let offset = max(0, date.timeIntervalSince(segment.start))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, self.activeSegment?.id == segment.id else { return }
            self.player.time = VLCTime(number: NSNumber(value: offset * 1_000))
        }
    }

    func stop() {
        player.stop()
    }

    private func play(url: URL, lowLatency: Bool) {
        player.stop()
        let media = VLCMedia(url: url)
        media.addOption(":rtsp-tcp")
        media.addOption(lowLatency ? ":network-caching=150" : ":network-caching=500")

        if let credentials {
            media.addOption(":rtsp-user=\(credentials.username)")
            media.addOption(":rtsp-pwd=\(credentials.password)")
        }

        player.media = media
        player.play()
    }
}

extension VLCPlaybackController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            switch self.player.state {
            case .playing:
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
                self.state = .failed(.cameraUnavailable)
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let segment = self.activeSegment {
                let elapsed = self.player.time.value?.doubleValue ?? 0
                self.currentDate = segment.start.addingTimeInterval(elapsed / 1_000)
                self.state = .archive(self.currentDate.clamped(to: segment.start...segment.end))
            } else {
                self.currentDate = Date()
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
