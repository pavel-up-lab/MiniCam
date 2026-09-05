import Foundation

enum ArchivePlaybackExperiment: String {
    case baseline
    case ffplayTCP = "ffplay-tcp"
    case ffplayUDP = "ffplay-udp"
    case foregroundOnly = "foreground-only"

    var usesFFplay: Bool {
        self == .ffplayUDP || self == .ffplayTCP
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
