import Foundation

struct ArchiveAnalysisSlice: Equatable, Sendable {
    let segment: RecordingSegment
    let start: Date
    let end: Date
}

struct ArchiveAnalysisCursor {
    private(set) var date: Date
    private let maximumBacklog: TimeInterval

    init(startingAt date: Date, maximumBacklog: TimeInterval = 60) {
        self.date = date
        self.maximumBacklog = maximumBacklog
    }

    mutating func takeNewSlices(
        from segments: [RecordingSegment]
    ) -> [ArchiveAnalysisSlice] {
        let ordered = segments.sorted { $0.start < $1.start }
        guard let newestEnd = ordered.map(\.end).max(), newestEnd > date else {
            return []
        }

        let lowerBound = max(date, newestEnd.addingTimeInterval(-maximumBacklog))
        var coveredUntil = lowerBound
        var slices: [ArchiveAnalysisSlice] = []

        for segment in ordered where segment.end > coveredUntil {
            let start = max(segment.start, coveredUntil)
            guard segment.end > start else { continue }
            slices.append(
                ArchiveAnalysisSlice(segment: segment, start: start, end: segment.end)
            )
            coveredUntil = segment.end
        }

        if let end = slices.last?.end {
            date = end
        }
        return slices
    }
}
