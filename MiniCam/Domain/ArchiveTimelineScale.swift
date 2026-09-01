import Foundation

struct ArchiveTimelineScale: Sendable {
    let secondsPerPoint: TimeInterval
    let liveSnapInterval: TimeInterval

    func date(
        from anchor: Date,
        translation: Double,
        range: ClosedRange<Date>
    ) -> Date {
        let candidate = anchor.addingTimeInterval(-translation * secondsPerPoint)
        return min(max(candidate, range.lowerBound), range.upperBound)
    }

    func snappedToLive(_ date: Date, live: Date) -> Date {
        guard live.timeIntervalSince(date) <= liveSnapInterval else {
            return date
        }
        return live
    }

    func date(
        atOverviewPosition position: Double,
        range: ClosedRange<Date>
    ) -> Date {
        let normalizedPosition = min(max(position, 0), 1)
        let duration = range.upperBound.timeIntervalSince(range.lowerBound)
        return range.lowerBound.addingTimeInterval(duration * normalizedPosition)
    }

    func overviewPosition(
        for date: Date,
        range: ClosedRange<Date>
    ) -> Double {
        let duration = range.upperBound.timeIntervalSince(range.lowerBound)
        guard duration > 0 else { return 1 }
        return min(max(date.timeIntervalSince(range.lowerBound) / duration, 0), 1)
    }
}
