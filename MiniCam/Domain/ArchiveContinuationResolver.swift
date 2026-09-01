import Foundation

enum ArchiveContinuationDestination: Equatable, Sendable {
    case archive(segment: RecordingSegment, date: Date)
}

struct ArchiveContinuationResolver: Sendable {
    let minimumRemainingDuration: TimeInterval
    let resumeOffset: TimeInterval

    func destination(
        after endedAt: Date,
        segments: [RecordingSegment]
    ) -> ArchiveContinuationDestination? {
        let continuationDate = endedAt.addingTimeInterval(resumeOffset)
        let sortedSegments = segments.sorted(by: { $0.start < $1.start })
        if let segment = sortedSegments.first(where: {
                $0.contains(endedAt)
                    && $0.end.timeIntervalSince(endedAt) >= minimumRemainingDuration
        }) {
            return .archive(segment: segment, date: continuationDate)
        }

        guard let next = sortedSegments.first(where: { $0.start >= endedAt }) else {
            return nil
        }

        return .archive(segment: next, date: next.start)
    }
}
