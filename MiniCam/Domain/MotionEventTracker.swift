import Foundation

struct MotionEventCandidate: Equatable, Sendable {
    let startedAt: Date
    let categories: [MotionObjectCategory]
}

struct MotionEventTracker {
    struct Configuration {
        let minimumConfidence: Double
        let minimumIntersection: Double
        let maximumCenterDistance: Double
        let minimumMovementDistance: Double
        let minimumSizeChange: Double
        let stationaryIntervals: Int
        let absenceTimeout: TimeInterval

        static let standard = Configuration(
            minimumConfidence: 0.30,
            minimumIntersection: 0.2,
            maximumCenterDistance: 0.15,
            minimumMovementDistance: 0.01,
            minimumSizeChange: 0.08,
            stationaryIntervals: 2,
            absenceTimeout: 30
        )
    }

    private struct Track {
        let id: UUID
        let category: MotionObjectCategory
        var bounds: CGRect
        var lastSeenAt: Date
        var isMoving: Bool
        var stationaryIntervals: Int
    }

    private let configuration: Configuration
    private var tracks: [Track] = []

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    mutating func process(
        _ detections: [ObjectDetection],
        at date: Date
    ) -> MotionEventCandidate? {
        tracks.removeAll {
            date.timeIntervalSince($0.lastSeenAt) >= configuration.absenceTimeout
        }

        var availableTrackIndices = Set(tracks.indices)
        var started: [(date: Date, category: MotionObjectCategory)] = []

        for detection in detections where detection.confidence >= configuration.minimumConfidence {
            guard let trackIndex = bestTrackIndex(
                for: detection,
                candidates: availableTrackIndices
            ) else {
                tracks.append(
                    Track(
                        id: UUID(),
                        category: detection.category,
                        bounds: detection.bounds,
                        lastSeenAt: date,
                        isMoving: false,
                        stationaryIntervals: 0
                    )
                )
                continue
            }

            availableTrackIndices.remove(trackIndex)
            var track = tracks[trackIndex]
            let moved = isMovement(from: track.bounds, to: detection.bounds)
            if moved {
                if !track.isMoving {
                    started.append((track.lastSeenAt, track.category))
                }
                track.isMoving = true
                track.stationaryIntervals = 0
            } else {
                track.stationaryIntervals += 1
                if track.stationaryIntervals >= configuration.stationaryIntervals {
                    track.isMoving = false
                }
            }
            track.bounds = detection.bounds
            track.lastSeenAt = date
            tracks[trackIndex] = track
        }

        guard let startedAt = started.map(\.date).min() else { return nil }
        let startedCategories = Set(started.map(\.category))
        let categories = MotionObjectCategory.allCases.filter(startedCategories.contains)
        return MotionEventCandidate(startedAt: startedAt, categories: categories)
    }

    private func bestTrackIndex(
        for detection: ObjectDetection,
        candidates: Set<Int>
    ) -> Int? {
        candidates
            .compactMap { index -> (index: Int, score: Double)? in
                let track = tracks[index]
                guard track.category == detection.category else { return nil }
                let intersection = intersectionOverUnion(track.bounds, detection.bounds)
                let distance = normalizedCenterDistance(track.bounds, detection.bounds)
                guard
                    intersection >= configuration.minimumIntersection
                        || distance <= configuration.maximumCenterDistance
                else {
                    return nil
                }
                let score = intersection >= configuration.minimumIntersection
                    ? 1 + intersection
                    : 1 - distance
                return (index, score)
            }
            .max { $0.score < $1.score }?
            .index
    }

    private func isMovement(from previous: CGRect, to current: CGRect) -> Bool {
        if normalizedCenterDistance(previous, current) >= configuration.minimumMovementDistance {
            return true
        }

        let widthChange = abs(current.width - previous.width) / max(previous.width, 0.001)
        let heightChange = abs(current.height - previous.height) / max(previous.height, 0.001)
        return max(widthChange, heightChange) >= configuration.minimumSizeChange
    }

    private func normalizedCenterDistance(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY) / sqrt(2)
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
