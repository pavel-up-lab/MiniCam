import Foundation

struct ArchiveCalendarAvailability: Sendable {
    let segments: [RecordingSegment]
    let calendar: Calendar

    func isDayAvailable(_ date: Date) -> Bool {
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            return false
        }

        return segments.contains(where: { segment in
            segment.start < interval.end && segment.end > interval.start
        })
    }

    func availableHours(on day: Date) -> Set<Int> {
        Set((0..<24).filter { hour in
            guard
                let hourDate = calendar.date(
                    bySettingHour: hour,
                    minute: 0,
                    second: 0,
                    of: day
                ),
                let interval = calendar.dateInterval(of: .hour, for: hourDate)
            else {
                return false
            }

            return segments.contains(where: { segment in
                segment.start < interval.end && segment.end > interval.start
            })
        })
    }

    func nearestPlayableDate(to requested: Date) -> Date? {
        guard let hour = calendar.dateInterval(of: .hour, for: requested) else {
            return nil
        }

        let intersectingSegments = segments.filter { segment in
            segment.start < hour.end && segment.end > hour.start
        }
        if intersectingSegments.contains(where: { $0.contains(requested) }) {
            return requested
        }

        let next = intersectingSegments
            .map { max($0.start, hour.start) }
            .filter { $0 >= requested && $0 < hour.end }
            .min()
        if let next {
            return next
        }

        return intersectingSegments
            .map { min($0.end, hour.end).addingTimeInterval(-0.001) }
            .filter { $0 >= hour.start && $0 <= requested }
            .max()
    }
}
