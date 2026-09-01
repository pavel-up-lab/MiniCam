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
    private var activePlaybackStart: Date?

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

    func playLive() {
        guard let profile, let url = profile.liveStreamURL() else {
            state = .failed(.invalidAddress)
            return
        }

        activeSegment = nil
        activePlaybackStart = nil
        currentDate = Date()
        state = .loading(nil)
        play(url: url, lowLatency: true)
    }

    func playArchive(segment: RecordingSegment, at date: Date) {
        guard
            let sourceURL = URL(string: segment.playbackURI),
            let url = HikvisionPlaybackURL.starting(sourceURL, at: date)
        else {
            state = .failed(.incompatibleArchive)
            return
        }

        activeSegment = segment
        activePlaybackStart = date
        currentDate = date
        state = .loading(date)
        play(url: url, lowLatency: false)
    }

    func stop() {
        player.stop()
    }

    private func play(url: URL, lowLatency: Bool) {
        player.stop()
        let media = VLCMedia(url: url)
        media.addOption(lowLatency ? ":network-caching=500" : ":network-caching=750")

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
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
