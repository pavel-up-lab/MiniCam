import Foundation

struct VideoClipSelection: Equatable, Sendable {
    let start: Date
    let end: Date
    let parts: [VideoClipPart]

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

struct VideoClipPart: Equatable, Sendable {
    let segment: RecordingSegment
    let start: Date
    let end: Date
}

struct VideoClipSelectionResolver {
    let maximumDuration: TimeInterval
    let minimumDuration: TimeInterval
    let adjoiningTolerance: TimeInterval

    init(
        maximumDuration: TimeInterval = 30 * 60,
        minimumDuration: TimeInterval = 1,
        adjoiningTolerance: TimeInterval = 1
    ) {
        self.maximumDuration = maximumDuration
        self.minimumDuration = minimumDuration
        self.adjoiningTolerance = adjoiningTolerance
    }

    func latestContinuousEnd(
        startingAt start: Date,
        segments: [RecordingSegment]
    ) -> Date? {
        let ordered = segments.sorted { $0.start < $1.start }
        guard let firstIndex = ordered.firstIndex(where: {
            $0.start <= start && start < $0.end
        }) else {
            return nil
        }

        let limit = start.addingTimeInterval(maximumDuration)
        var continuousEnd = ordered[firstIndex].end

        for segment in ordered.dropFirst(firstIndex + 1) {
            guard continuousEnd < limit else { break }
            guard segment.start <= continuousEnd.addingTimeInterval(adjoiningTolerance) else {
                break
            }
            continuousEnd = max(continuousEnd, segment.end)
        }

        return min(continuousEnd, limit)
    }

    func resolve(
        from start: Date,
        to requestedEnd: Date,
        segments: [RecordingSegment]
    ) throws -> VideoClipSelection {
        guard requestedEnd.timeIntervalSince(start) >= minimumDuration else {
            throw VideoClipSelectionError.tooShort
        }
        guard let availableEnd = latestContinuousEnd(
            startingAt: start,
            segments: segments
        ) else {
            throw VideoClipSelectionError.startUnavailable
        }

        let end = min(
            requestedEnd,
            start.addingTimeInterval(maximumDuration)
        )
        guard end <= availableEnd else {
            throw VideoClipSelectionError.archiveGap
        }

        let ordered = segments.sorted { $0.start < $1.start }
        var parts: [VideoClipPart] = []
        var coveredUntil = start

        for segment in ordered where segment.end > start && segment.start < end {
            guard segment.start <= coveredUntil.addingTimeInterval(adjoiningTolerance) else {
                throw VideoClipSelectionError.archiveGap
            }

            let partStart = max(start, segment.start)
            let partEnd = min(end, segment.end)
            guard partEnd > partStart else { continue }
            parts.append(
                VideoClipPart(
                    segment: segment,
                    start: partStart,
                    end: partEnd
                )
            )
            coveredUntil = max(coveredUntil, segment.end)
            if coveredUntil >= end { break }
        }

        guard coveredUntil >= end, !parts.isEmpty else {
            throw VideoClipSelectionError.archiveGap
        }
        return VideoClipSelection(start: start, end: end, parts: parts)
    }
}

enum VideoClipSelectionError: LocalizedError, Equatable {
    case tooShort
    case startUnavailable
    case archiveGap

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "Выберите фрагмент длительностью не меньше одной секунды."
        case .startUnavailable:
            return "В начальной точке нет архивной записи."
        case .archiveGap:
            return "Выбранный фрагмент пересекает разрыв архивной записи."
        }
    }
}
