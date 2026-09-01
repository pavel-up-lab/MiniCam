import Foundation

enum ArchiveStepDestination: Equatable, Sendable {
    case live
    case archive(segment: RecordingSegment, date: Date)
}

struct ArchiveStepResolver: Sendable {
    let liveSnapInterval: TimeInterval

    func destination(
        from currentDate: Date,
        offset: TimeInterval,
        segments: [RecordingSegment],
        liveDate: Date
    ) -> ArchiveStepDestination? {
        let sortedSegments = segments.sorted { $0.start < $1.start }
        guard let first = sortedSegments.first, let last = sortedSegments.last else {
            return nil
        }

        let target = currentDate.addingTimeInterval(offset)
        if target >= liveDate.addingTimeInterval(-liveSnapInterval) {
            return .live
        }

        if target <= first.start {
            return .archive(segment: first, date: first.start)
        }

        if let segment = sortedSegments.first(where: { $0.contains(target) }) {
            return .archive(segment: segment, date: target)
        }

        if offset < 0 {
            guard let previous = sortedSegments.last(where: { $0.end <= target }) else {
                return .archive(segment: first, date: first.start)
            }
            return .archive(segment: previous, date: lastPlayableDate(in: previous))
        }

        if let next = sortedSegments.first(where: { $0.start >= target }) {
            return .archive(segment: next, date: next.start)
        }

        return .archive(segment: last, date: lastPlayableDate(in: last))
    }

    private func lastPlayableDate(in segment: RecordingSegment) -> Date {
        max(segment.start, segment.end.addingTimeInterval(-0.001))
    }
}
