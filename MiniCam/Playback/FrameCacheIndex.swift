import Foundation

struct FrameCacheEntry: Equatable, Sendable {
    let date: Date
    let fileURL: URL
}

struct FrameCacheIndex {
    private(set) var entries: [FrameCacheEntry]

    init(entries: [FrameCacheEntry] = []) {
        self.entries = entries.sorted { $0.date < $1.date }
    }

    mutating func insert(_ entry: FrameCacheEntry) {
        let position = insertionIndex(for: entry.date)
        if entries.indices.contains(position), entries[position].date == entry.date {
            entries[position] = entry
        } else {
            entries.insert(entry, at: position)
        }
    }

    func nearest(to date: Date, maxDistance: TimeInterval) -> FrameCacheEntry? {
        guard !entries.isEmpty else { return nil }

        let position = insertionIndex(for: date)
        var nearest: FrameCacheEntry?

        if position > entries.startIndex {
            nearest = entries[entries.index(before: position)]
        }
        if entries.indices.contains(position) {
            let candidate = entries[position]
            if
                nearest == nil
                    || abs(candidate.date.timeIntervalSince(date))
                    < abs(nearest!.date.timeIntervalSince(date))
            {
                nearest = candidate
            }
        }

        guard
            let nearest,
            abs(nearest.date.timeIntervalSince(date)) <= maxDistance
        else {
            return nil
        }
        return nearest
    }

    mutating func remove(olderThan cutoff: Date) -> [FrameCacheEntry] {
        let firstRetained = insertionIndex(for: cutoff)
        guard firstRetained > entries.startIndex else { return [] }

        let removed = Array(entries[..<firstRetained])
        entries.removeFirst(firstRetained)
        return removed
    }

    private func insertionIndex(for date: Date) -> Int {
        var lower = entries.startIndex
        var upper = entries.endIndex

        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if entries[middle].date < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

enum FrameCacheRetention {
    static let duration: TimeInterval = 36 * 60 * 60

    static func cutoff(
        at referenceDate: Date,
        duration: TimeInterval = duration
    ) -> Date {
        referenceDate.addingTimeInterval(-duration)
    }
}
