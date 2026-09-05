import Foundation

enum PlaybackArchitecture {
    case arm64
    case x86_64
    case other

    static var current: PlaybackArchitecture {
#if arch(arm64)
        return .arm64
#elseif arch(x86_64)
        return .x86_64
#else
        return .other
#endif
    }
}

enum ArchivePlaybackExperiment: String {
    case baseline
    case defaultFramePolicy = "default-frame-policy"
    case ffplayTCP = "ffplay-tcp"
    case ffplayUDP = "ffplay-udp"
    case foregroundOnly = "foreground-only"
    case softwareDecoding = "software-decoding"

    var usesFFplay: Bool {
        self == .ffplayUDP || self == .ffplayTCP
    }

    var usesBackgroundPlayback: Bool {
        self == .baseline || self == .defaultFramePolicy || self == .softwareDecoding
    }

    func usesSoftwareDecoding(lowLatency: Bool) -> Bool {
        self == .softwareDecoding && !lowLatency
    }

    func usesDefaultFramePolicy(
        lowLatency: Bool,
        architecture: PlaybackArchitecture = .current
    ) -> Bool {
        guard !lowLatency else { return false }

        if self == .defaultFramePolicy {
            return true
        }

        return architecture == .arm64
            && (self == .baseline || self == .foregroundOnly)
    }

    static var current: ArchivePlaybackExperiment {
        resolve(
            arguments: ProcessInfo.processInfo.arguments,
            debugEnabled: _isDebugAssertConfiguration()
        )
    }

    static func resolve(
        arguments: [String],
        debugEnabled: Bool
    ) -> ArchivePlaybackExperiment {
        guard debugEnabled else { return .baseline }
        let prefix = "--archive-playback-experiment="
        let values = arguments.compactMap { argument -> String? in
            guard argument.hasPrefix(prefix) else { return nil }
            return String(argument.dropFirst(prefix.count))
        }
        guard
            values.count == 1,
            let value = values.first,
            let experiment = ArchivePlaybackExperiment(rawValue: value)
        else {
            return .baseline
        }
        return experiment
    }
}
