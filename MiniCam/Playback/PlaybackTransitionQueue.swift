import Foundation

enum PlaybackArchitecture {
    case intel
    case appleSilicon

    static var current: Self {
#if arch(x86_64)
        .intel
#else
        .appleSilicon
#endif
    }
}

struct VLCPlaybackOptions {
    static func playerOptions(
        for architecture: PlaybackArchitecture
    ) -> [String] {
        var options = [
            "--no-video-title-show",
            "--no-snapshot-preview",
            "--network-caching=500",
            "--live-caching=500"
        ]

        if architecture == .appleSilicon {
            options += [
                "--no-drop-late-frames",
                "--no-skip-frames"
            ]
        }
        return options
    }
}

struct LivePlaybackRequestGate {
    let duplicateWindow: TimeInterval
    private var lastAcceptedAt: Date?

    init(duplicateWindow: TimeInterval = 1) {
        self.duplicateWindow = duplicateWindow
    }

    mutating func shouldAccept(at date: Date = Date()) -> Bool {
        if
            let lastAcceptedAt,
            date.timeIntervalSince(lastAcceptedAt) < duplicateWindow
        {
            return false
        }
        lastAcceptedAt = date
        return true
    }

    mutating func reset() {
        lastAcceptedAt = nil
    }
}

struct PlaybackTransitionQueue<Request> {
    enum Action: Equatable {
        case startNow
        case stopPlayer
        case wait
    }

    private var pendingRequest: Request?
    private(set) var isWaitingForStop = false

    mutating func schedule(
        _ request: Request,
        playerNeedsStop: Bool
    ) -> Action {
        pendingRequest = request

        if isWaitingForStop {
            return .wait
        }
        guard playerNeedsStop else {
            pendingRequest = nil
            return .startNow
        }

        isWaitingForStop = true
        return .stopPlayer
    }

    mutating func finishStopping() -> Request? {
        guard isWaitingForStop else { return nil }
        isWaitingForStop = false
        defer { pendingRequest = nil }
        return pendingRequest
    }

    mutating func reset() {
        pendingRequest = nil
        isWaitingForStop = false
    }
}
